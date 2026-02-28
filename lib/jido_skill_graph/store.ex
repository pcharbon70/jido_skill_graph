defmodule JidoSkillGraph.Store do
  @moduledoc """
  In-memory snapshot holder with atomic publish semantics.

  Snapshots are published to `:persistent_term` so readers can access the current
  snapshot without blocking on the GenServer process.
  """

  use GenServer

  alias JidoSkillGraph.SearchIndex.Trigram
  alias JidoSkillGraph.Snapshot
  alias JidoSkillGraph.Telemetry

  @type state :: %{
          name: GenServer.name() | nil,
          persistent_key: term(),
          snapshot: Snapshot.t() | nil,
          ets_nodes: term() | nil,
          ets_edges: term() | nil,
          ets_search_postings: term() | nil,
          ets_search_docs: term() | nil,
          ets_search_trigrams: term() | nil,
          ets_search_bodies: term() | nil,
          version: non_neg_integer(),
          updated_at: DateTime.t() | nil
        }

  @type metadata :: %{
          version: non_neg_integer(),
          updated_at: DateTime.t() | nil,
          persistent_key: term()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec current_snapshot(GenServer.name()) :: Snapshot.t() | nil
  def current_snapshot(server \\ __MODULE__) do
    case persistent_key_for(server) do
      {:ok, key} -> :persistent_term.get(key, nil)
      :unknown -> GenServer.call(server, :current_snapshot)
    end
  end

  @spec swap_snapshot(GenServer.name(), Snapshot.t()) :: {:ok, Snapshot.t()} | {:error, term()}
  def swap_snapshot(server \\ __MODULE__, %Snapshot{} = snapshot) do
    GenServer.call(server, {:swap_snapshot, snapshot})
  end

  @spec metadata(GenServer.name()) :: metadata()
  def metadata(server \\ __MODULE__) do
    GenServer.call(server, :metadata)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    persistent_key = Keyword.get(opts, :persistent_key, persistent_key(name))

    state = %{
      name: name,
      persistent_key: persistent_key,
      snapshot: nil,
      ets_nodes: nil,
      ets_edges: nil,
      ets_search_postings: nil,
      ets_search_docs: nil,
      ets_search_trigrams: nil,
      ets_search_bodies: nil,
      version: 0,
      updated_at: nil
    }

    :persistent_term.put(persistent_key, nil)

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    :persistent_term.erase(state.persistent_key)
    maybe_delete_table(state.ets_nodes)
    maybe_delete_table(state.ets_edges)
    maybe_delete_table(state.ets_search_postings)
    maybe_delete_table(state.ets_search_docs)
    maybe_delete_table(state.ets_search_trigrams)
    maybe_delete_table(state.ets_search_bodies)
    :ok
  end

  @impl true
  def handle_call(:current_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_call(:metadata, _from, state) do
    {:reply,
     %{
       version: state.version,
       updated_at: state.updated_at,
       persistent_key: state.persistent_key
     }, state}
  end

  @impl true
  def handle_call({:swap_snapshot, %Snapshot{} = snapshot}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    started_at = System.monotonic_time()

    next_snapshot =
      if snapshot.version < state.version do
        %{snapshot | version: state.version + 1}
      else
        snapshot
      end

    next_state = %{
      state
      | snapshot: next_snapshot,
        version: next_snapshot.version,
        updated_at: now
    }

    case build_ets_indexes(next_snapshot) do
      {:ok, ets_nodes, ets_edges, ets_search_postings, ets_search_docs, ets_search_trigrams,
       ets_search_bodies} ->
        indexed_snapshot =
          Snapshot.attach_ets(
            next_snapshot,
            ets_nodes,
            ets_edges,
            ets_search_postings,
            ets_search_docs,
            ets_search_trigrams,
            ets_search_bodies
          )

        :persistent_term.put(state.persistent_key, indexed_snapshot)

        maybe_delete_replaced_table(state.ets_nodes, ets_nodes)
        maybe_delete_replaced_table(state.ets_edges, ets_edges)
        maybe_delete_replaced_table(state.ets_search_postings, ets_search_postings)
        maybe_delete_replaced_table(state.ets_search_docs, ets_search_docs)
        maybe_delete_replaced_table(state.ets_search_trigrams, ets_search_trigrams)
        maybe_delete_replaced_table(state.ets_search_bodies, ets_search_bodies)
        emit_swap_telemetry(started_at, :ok, indexed_snapshot)

        {:reply, {:ok, indexed_snapshot},
         %{
           next_state
           | snapshot: indexed_snapshot,
             ets_nodes: ets_nodes,
             ets_edges: ets_edges,
             ets_search_postings: ets_search_postings,
             ets_search_docs: ets_search_docs,
             ets_search_trigrams: ets_search_trigrams,
             ets_search_bodies: ets_search_bodies
         }}

      {:error, reason} ->
        emit_swap_failure_telemetry(started_at, reason)
        {:reply, {:error, reason}, state}
    end
  end

  @spec persistent_key(GenServer.name()) :: term()
  def persistent_key(name), do: {__MODULE__, name, :snapshot}

  defp persistent_key_for(name) when is_atom(name) or is_tuple(name),
    do: {:ok, persistent_key(name)}

  defp persistent_key_for(_name), do: :unknown

  defp build_ets_indexes(%Snapshot{} = snapshot) do
    node_table_opts = [:set, :protected, {:read_concurrency, true}, {:write_concurrency, false}]

    edge_table_opts = [
      :duplicate_bag,
      :protected,
      {:read_concurrency, true},
      {:write_concurrency, false}
    ]

    posting_table_opts = [
      :duplicate_bag,
      :protected,
      {:read_concurrency, true},
      {:write_concurrency, false}
    ]

    doc_stats_table_opts = [
      :set,
      :protected,
      {:read_concurrency, true},
      {:write_concurrency, false}
    ]

    body_cache_table_opts = [
      :set,
      :protected,
      {:read_concurrency, true},
      {:write_concurrency, false}
    ]

    trigram_table_opts = [
      :duplicate_bag,
      :protected,
      {:read_concurrency, true},
      {:write_concurrency, false}
    ]

    table_specs = [
      {:ets_nodes, node_table_opts},
      {:ets_edges, edge_table_opts},
      {:ets_search_postings, posting_table_opts},
      {:ets_search_docs, doc_stats_table_opts},
      {:ets_search_bodies, body_cache_table_opts},
      {:ets_search_trigrams, trigram_table_opts}
    ]

    case create_index_tables(table_specs, %{}) do
      {:ok, tables} ->
        case populate_index_tables(snapshot, tables) do
          :ok ->
            {:ok, tables.ets_nodes, tables.ets_edges, tables.ets_search_postings,
             tables.ets_search_docs, tables.ets_search_trigrams, tables.ets_search_bodies}

          {:error, reason} ->
            maybe_delete_tables(Map.values(tables))
            {:error, {:ets_index_build_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:ets_index_build_failed, reason}}
    end
  end

  defp create_index_tables([], tables), do: {:ok, tables}

  defp create_index_tables([{key, opts} | rest], tables) do
    case new_ets_table(opts) do
      {:ok, table} ->
        create_index_tables(rest, Map.put(tables, key, table))

      {:error, reason} ->
        maybe_delete_tables(Map.values(tables))
        {:error, reason}
    end
  end

  defp populate_index_tables(%Snapshot{} = snapshot, tables) do
    with :ok <- insert_nodes(tables.ets_nodes, snapshot.nodes),
         :ok <- insert_edges(tables.ets_edges, snapshot.edges),
         :ok <- insert_search_postings(tables.ets_search_postings, snapshot),
         :ok <- insert_search_doc_stats(tables.ets_search_docs, snapshot),
         :ok <- insert_search_body_cache(tables.ets_search_bodies, snapshot) do
      insert_search_trigrams(tables.ets_search_trigrams, snapshot)
    end
  end

  defp new_ets_table(opts) do
    {:ok, :ets.new(__MODULE__, opts)}
  catch
    kind, reason -> {:error, {:new_table_failed, {kind, reason}}}
  end

  defp insert_nodes(ets_nodes, nodes) do
    rows = Enum.map(nodes, fn {id, node} -> {id, node} end)
    true = :ets.insert(ets_nodes, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_nodes_failed, {kind, reason}}}
  end

  defp insert_edges(ets_edges, edges) do
    rows =
      Enum.flat_map(edges, fn edge ->
        [
          {:all, edge},
          {{:out, edge.from}, edge},
          {{:in, edge.to}, edge}
        ]
      end)

    true = :ets.insert(ets_edges, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_edges_failed, {kind, reason}}}
  end

  defp insert_search_postings(ets_search_postings, %Snapshot{} = snapshot) do
    postings =
      snapshot
      |> search_index_meta()
      |> Map.get(:postings, %{})

    rows =
      postings
      |> Enum.flat_map(fn {{term, field}, node_rows} ->
        Enum.map(node_rows, fn {node_id, tf} -> {{term, field}, node_id, tf} end)
      end)

    true = :ets.insert(ets_search_postings, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_search_postings_failed, {kind, reason}}}
  end

  defp insert_search_doc_stats(ets_search_docs, %Snapshot{} = snapshot) do
    field_lengths_by_doc =
      snapshot
      |> search_index_meta()
      |> Map.get(:field_lengths_by_doc, %{})

    rows =
      field_lengths_by_doc
      |> Enum.map(fn {node_id, field_lengths} -> {node_id, field_lengths} end)
      |> then(&[{:__meta__, Snapshot.search_corpus_stats(snapshot)} | &1])

    true = :ets.insert(ets_search_docs, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_search_doc_stats_failed, {kind, reason}}}
  end

  defp insert_search_body_cache(ets_search_bodies, %Snapshot{} = snapshot) do
    rows =
      snapshot
      |> search_index_meta()
      |> Map.get(:body_cache, %{})
      |> Enum.map(fn {node_id, body} -> {node_id, body} end)

    true = :ets.insert(ets_search_bodies, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_search_body_cache_failed, {kind, reason}}}
  end

  defp insert_search_trigrams(ets_search_trigrams, %Snapshot{} = snapshot) do
    terms =
      snapshot
      |> search_index_meta()
      |> Map.get(:document_frequencies, %{})
      |> Map.keys()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()
      |> Enum.sort()

    trigram_rows =
      terms
      |> Enum.flat_map(&Trigram.dictionary_entries/1)
      |> Enum.uniq()
      |> Enum.sort()

    trigram_count =
      trigram_rows
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()
      |> MapSet.size()

    meta_row =
      {:__meta__,
       %{
         enabled: trigram_count > 0,
         graph_id: snapshot.graph_id,
         terms: length(terms),
         trigram_count: trigram_count
       }}

    rows = [meta_row | trigram_rows]
    true = :ets.insert(ets_search_trigrams, rows)
    :ok
  catch
    kind, reason -> {:error, {:insert_search_trigrams_failed, {kind, reason}}}
  end

  defp search_index_meta(%Snapshot{search_index: nil}), do: %{}
  defp search_index_meta(%Snapshot{search_index: search_index}), do: search_index.meta

  defp maybe_delete_replaced_table(old, new) when old == new, do: :ok
  defp maybe_delete_replaced_table(old, _new), do: maybe_delete_table(old)

  defp maybe_delete_tables(tables) do
    tables
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&maybe_delete_table/1)

    :ok
  end

  defp maybe_delete_table(nil), do: :ok

  defp maybe_delete_table(table) do
    :ets.delete(table)
    :ok
  catch
    :error, :badarg -> :ok
    :exit, :badarg -> :ok
  end

  defp emit_swap_telemetry(started_at, status, snapshot) do
    search_term_count =
      snapshot
      |> search_index_meta()
      |> Map.get(:postings, %{})
      |> map_size()

    metadata = %{
      status: status,
      graph_id: snapshot.graph_id,
      version: snapshot.version,
      node_count: Snapshot.node_ids(snapshot) |> length(),
      edge_count: Snapshot.edges(snapshot) |> length(),
      search_term_count: search_term_count
    }

    emit_snapshot_swap_telemetry(started_at, metadata)
  end

  defp emit_swap_failure_telemetry(started_at, reason) do
    metadata = %{
      status: :error,
      reason: inspect(reason)
    }

    emit_snapshot_swap_telemetry(started_at, metadata)
  end

  defp emit_snapshot_swap_telemetry(started_at, metadata) do
    duration_native = System.monotonic_time() - started_at

    Telemetry.execute(
      [:store, :snapshot_swap],
      Telemetry.duration_measurements(duration_native),
      metadata
    )
  end
end
