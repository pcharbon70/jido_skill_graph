defmodule JidoSkillGraph.Store do
  @moduledoc """
  In-memory snapshot holder with atomic publish semantics.

  Snapshots are published to `:persistent_term` so readers can access the current
  snapshot without blocking on the GenServer process.
  """

  use GenServer

  alias JidoSkillGraph.Snapshot

  @type state :: %{
          name: GenServer.name() | nil,
          persistent_key: term(),
          snapshot: Snapshot.t() | nil,
          ets_nodes: term() | nil,
          ets_edges: term() | nil,
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
      {:ok, ets_nodes, ets_edges} ->
        indexed_snapshot = Snapshot.attach_ets(next_snapshot, ets_nodes, ets_edges)

        :persistent_term.put(state.persistent_key, indexed_snapshot)

        maybe_delete_replaced_table(state.ets_nodes, ets_nodes)
        maybe_delete_replaced_table(state.ets_edges, ets_edges)

        {:reply, {:ok, indexed_snapshot},
         %{next_state | snapshot: indexed_snapshot, ets_nodes: ets_nodes, ets_edges: ets_edges}}

      {:error, reason} ->
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

    case new_ets_table(node_table_opts) do
      {:ok, ets_nodes} -> build_ets_indexes(snapshot, ets_nodes, edge_table_opts)
      {:error, reason} -> {:error, {:ets_index_build_failed, reason}}
    end
  end

  defp build_ets_indexes(%Snapshot{} = snapshot, ets_nodes, edge_table_opts) do
    case new_ets_table(edge_table_opts) do
      {:ok, ets_edges} ->
        populate_ets_indexes(snapshot, ets_nodes, ets_edges)

      {:error, reason} ->
        maybe_delete_table(ets_nodes)
        {:error, {:ets_index_build_failed, reason}}
    end
  end

  defp populate_ets_indexes(%Snapshot{} = snapshot, ets_nodes, ets_edges) do
    with :ok <- insert_nodes(ets_nodes, snapshot.nodes),
         :ok <- insert_edges(ets_edges, snapshot.edges) do
      {:ok, ets_nodes, ets_edges}
    else
      {:error, reason} ->
        maybe_delete_table(ets_nodes)
        maybe_delete_table(ets_edges)
        {:error, {:ets_index_build_failed, reason}}
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

  defp maybe_delete_replaced_table(old, new) when old == new, do: :ok
  defp maybe_delete_replaced_table(old, _new), do: maybe_delete_table(old)

  defp maybe_delete_table(nil), do: :ok

  defp maybe_delete_table(table) do
    :ets.delete(table)
    :ok
  catch
    :error, :badarg -> :ok
    :exit, :badarg -> :ok
  end
end
