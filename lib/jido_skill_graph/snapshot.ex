defmodule JidoSkillGraph.Snapshot do
  @moduledoc """
  Snapshot model and unresolved-link policy contract.
  """

  alias JidoSkillGraph.{Edge, Node, SearchIndex}
  alias JidoSkillGraph.SearchIndex.Trigram

  @type unresolved_link_policy :: :warn_and_skip | :error | :placeholder

  @policies [:warn_and_skip, :error, :placeholder]

  @enforce_keys [:graph_id, :version, :nodes, :edges, :unresolved_link_policy]
  defstruct [
    :graph,
    :graph_id,
    :manifest,
    :version,
    :unresolved_link_policy,
    :search_index,
    :ets_nodes,
    :ets_edges,
    :ets_search_postings,
    :ets_search_docs,
    :ets_search_trigrams,
    :ets_search_bodies,
    nodes: %{},
    edges: [],
    warnings: [],
    stats: %{}
  ]

  @type t :: %__MODULE__{
          graph: Graph.t() | nil,
          graph_id: String.t(),
          manifest: term(),
          version: non_neg_integer(),
          unresolved_link_policy: unresolved_link_policy(),
          search_index: SearchIndex.t() | nil,
          ets_nodes: term() | nil,
          ets_edges: term() | nil,
          ets_search_postings: term() | nil,
          ets_search_docs: term() | nil,
          ets_search_trigrams: term() | nil,
          ets_search_bodies: term() | nil,
          nodes: %{required(String.t()) => Node.t()},
          edges: [Edge.t()],
          warnings: [String.t()],
          stats: map()
        }

  @type option ::
          {:graph, Graph.t() | nil}
          | {:graph_id, String.t()}
          | {:manifest, term()}
          | {:version, non_neg_integer()}
          | {:unresolved_link_policy, unresolved_link_policy()}
          | {:search_index, SearchIndex.t() | nil | keyword()}
          | {:ets_nodes, term() | nil}
          | {:ets_edges, term() | nil}
          | {:ets_search_postings, term() | nil}
          | {:ets_search_docs, term() | nil}
          | {:ets_search_trigrams, term() | nil}
          | {:ets_search_bodies, term() | nil}
          | {:nodes, [Node.t()] | %{optional(String.t()) => Node.t()}}
          | {:edges, [Edge.t()]}
          | {:warnings, [String.t()]}
          | {:stats, map()}

  @spec policies() :: [unresolved_link_policy()]
  def policies, do: @policies

  @spec valid_policy?(term()) :: boolean()
  def valid_policy?(policy), do: policy in @policies

  @spec new([option()]) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    graph_id = Keyword.get(opts, :graph_id)
    policy = Keyword.get(opts, :unresolved_link_policy, :warn_and_skip)

    with :ok <- validate_graph_id(graph_id),
         :ok <- validate_policy(policy),
         {:ok, nodes} <- normalize_nodes(graph_id, Keyword.get(opts, :nodes, [])),
         {:ok, edges} <- normalize_edges(Keyword.get(opts, :edges, [])),
         {:ok, search_index} <- normalize_search_index(Keyword.get(opts, :search_index)),
         {:ok, nodes, edges, warnings} <- resolve_edges(nodes, edges, graph_id, policy, []) do
      {:ok,
       %__MODULE__{
         graph: Keyword.get(opts, :graph),
         graph_id: graph_id,
         manifest: Keyword.get(opts, :manifest),
         version: Keyword.get(opts, :version, 0),
         unresolved_link_policy: policy,
         search_index: search_index,
         ets_nodes: Keyword.get(opts, :ets_nodes),
         ets_edges: Keyword.get(opts, :ets_edges),
         ets_search_postings: Keyword.get(opts, :ets_search_postings),
         ets_search_docs: Keyword.get(opts, :ets_search_docs),
         ets_search_trigrams: Keyword.get(opts, :ets_search_trigrams),
         ets_search_bodies: Keyword.get(opts, :ets_search_bodies),
         nodes: nodes,
         edges: edges,
         warnings: Keyword.get(opts, :warnings, []) ++ Enum.reverse(warnings),
         stats: Keyword.get(opts, :stats, %{})
       }}
    end
  end

  defp normalize_nodes(graph_id, nodes) when is_list(nodes) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn
      %Node{id: id} = node, {:ok, acc} ->
        if Map.has_key?(acc, id) do
          {:halt, {:error, {:duplicate_node_id, id}}}
        else
          {:cont, {:ok, Map.put(acc, id, node)}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_nodes}}
    end)
    |> ensure_graph_id_alignment(graph_id)
  end

  defp normalize_nodes(graph_id, nodes) when is_map(nodes) do
    nodes
    |> Enum.reduce_while({:ok, %{}}, fn
      {id, %Node{id: node_id} = node}, {:ok, acc} ->
        cond do
          id != node_id -> {:halt, {:error, {:mismatched_node_key, id, node_id}}}
          Map.has_key?(acc, id) -> {:halt, {:error, {:duplicate_node_id, id}}}
          true -> {:cont, {:ok, Map.put(acc, id, node)}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_nodes}}
    end)
    |> ensure_graph_id_alignment(graph_id)
  end

  defp normalize_nodes(_graph_id, _nodes), do: {:error, :invalid_nodes}

  defp normalize_edges(edges) when is_list(edges) do
    if Enum.all?(edges, &match?(%Edge{}, &1)) do
      {:ok, edges}
    else
      {:error, :invalid_edges}
    end
  end

  defp normalize_edges(_edges), do: {:error, :invalid_edges}

  defp resolve_edges(nodes, edges, _graph_id, :error, warnings) do
    Enum.reduce_while(edges, {:ok, nodes, [], warnings}, fn edge,
                                                            {:ok, acc_nodes, acc_edges, acc_warn} ->
      case missing_nodes(acc_nodes, edge) do
        [] -> {:cont, {:ok, acc_nodes, [edge | acc_edges], acc_warn}}
        missing -> {:halt, {:error, {:unresolved_edge, edge, missing}}}
      end
    end)
    |> reverse_edges()
  end

  defp resolve_edges(nodes, edges, _graph_id, :warn_and_skip, warnings) do
    Enum.reduce(edges, {:ok, nodes, [], warnings}, fn edge,
                                                      {:ok, acc_nodes, acc_edges, acc_warn} ->
      case missing_nodes(acc_nodes, edge) do
        [] -> {:ok, acc_nodes, [edge | acc_edges], acc_warn}
        missing -> {:ok, acc_nodes, acc_edges, [warning_for(edge, missing, :skipped) | acc_warn]}
      end
    end)
    |> reverse_edges()
  end

  defp resolve_edges(nodes, edges, graph_id, :placeholder, warnings) do
    Enum.reduce(edges, {:ok, nodes, [], warnings}, fn edge,
                                                      {:ok, acc_nodes, acc_edges, acc_warn} ->
      {next_nodes, next_warn} = ensure_placeholder_nodes(acc_nodes, edge, graph_id, acc_warn)
      {:ok, next_nodes, [edge | acc_edges], next_warn}
    end)
    |> reverse_edges()
  end

  defp reverse_edges({:ok, nodes, edges, warnings}),
    do: {:ok, nodes, Enum.reverse(edges), warnings}

  defp reverse_edges(error), do: error

  defp ensure_placeholder_nodes(nodes, %Edge{} = edge, graph_id, warnings) do
    [edge.from, edge.to]
    |> Enum.uniq()
    |> Enum.reduce({nodes, warnings}, fn node_id, {acc_nodes, acc_warn} ->
      if Map.has_key?(acc_nodes, node_id) do
        {acc_nodes, acc_warn}
      else
        placeholder = Node.placeholder(graph_id || infer_graph_id(acc_nodes), node_id)

        {
          Map.put(acc_nodes, placeholder.id, placeholder),
          ["placeholder node created for unresolved id '#{placeholder.id}'" | acc_warn]
        }
      end
    end)
  end

  defp infer_graph_id(nodes) do
    case Map.values(nodes) do
      [%Node{graph_id: graph_id} | _] -> graph_id
      _ -> "default"
    end
  end

  defp missing_nodes(nodes, %Edge{} = edge) do
    [edge.from, edge.to]
    |> Enum.reject(&Map.has_key?(nodes, &1))
  end

  defp warning_for(edge, missing, action) do
    "unresolved edge #{edge.from} -> #{edge.to} (missing: #{Enum.join(missing, ",")}) #{action}"
  end

  defp ensure_graph_id_alignment({:ok, nodes}, graph_id) do
    if Enum.all?(nodes, fn {_id, node} -> node.graph_id == graph_id end) do
      {:ok, nodes}
    else
      {:error, :node_graph_id_mismatch}
    end
  end

  defp ensure_graph_id_alignment(error, _graph_id), do: error

  defp validate_graph_id(graph_id) when is_binary(graph_id) and graph_id != "", do: :ok
  defp validate_graph_id(_graph_id), do: {:error, :invalid_graph_id}

  defp validate_policy(policy) do
    if valid_policy?(policy) do
      :ok
    else
      {:error, {:invalid_unresolved_link_policy, policy}}
    end
  end

  defp normalize_search_index(nil), do: {:ok, nil}
  defp normalize_search_index(%SearchIndex{} = search_index), do: {:ok, search_index}

  defp normalize_search_index(search_index_opts) when is_list(search_index_opts) do
    case SearchIndex.new(search_index_opts) do
      {:ok, %SearchIndex{} = search_index} -> {:ok, search_index}
      {:error, reason} -> {:error, {:invalid_search_index, reason}}
    end
  end

  defp normalize_search_index(_search_index),
    do: {:error, {:invalid_search_index, :invalid_shape}}

  @spec attach_ets(t(), term(), term()) :: t()
  def attach_ets(%__MODULE__{} = snapshot, ets_nodes, ets_edges) do
    %{snapshot | ets_nodes: ets_nodes, ets_edges: ets_edges}
  end

  @spec attach_ets(t(), term(), term(), term(), term(), term()) :: t()
  def attach_ets(
        %__MODULE__{} = snapshot,
        ets_nodes,
        ets_edges,
        ets_search_postings,
        ets_search_docs,
        ets_search_trigrams
      ) do
    attach_ets(
      snapshot,
      ets_nodes,
      ets_edges,
      ets_search_postings,
      ets_search_docs,
      ets_search_trigrams,
      nil
    )
  end

  @spec attach_ets(t(), term(), term(), term(), term(), term(), term()) :: t()
  def attach_ets(
        %__MODULE__{} = snapshot,
        ets_nodes,
        ets_edges,
        ets_search_postings,
        ets_search_docs,
        ets_search_trigrams,
        ets_search_bodies
      ) do
    %{
      snapshot
      | ets_nodes: ets_nodes,
        ets_edges: ets_edges,
        ets_search_postings: ets_search_postings,
        ets_search_docs: ets_search_docs,
        ets_search_trigrams: ets_search_trigrams,
        ets_search_bodies: ets_search_bodies
    }
  end

  @spec node_ids(t()) :: [String.t()]
  def node_ids(%__MODULE__{ets_nodes: ets_nodes} = snapshot) when not is_nil(ets_nodes) do
    case safe_ets_tab2list(ets_nodes) do
      [] -> Map.keys(snapshot.nodes)
      rows -> Enum.map(rows, fn {id, _node} -> id end)
    end
  end

  def node_ids(%__MODULE__{nodes: nodes}), do: Map.keys(nodes)

  @spec nodes(t()) :: [Node.t()]
  def nodes(%__MODULE__{ets_nodes: ets_nodes} = snapshot) when not is_nil(ets_nodes) do
    case safe_ets_tab2list(ets_nodes) do
      [] -> Map.values(snapshot.nodes)
      rows -> Enum.map(rows, fn {_id, node} -> node end)
    end
  end

  def nodes(%__MODULE__{nodes: nodes}), do: Map.values(nodes)

  @spec get_node(t(), String.t()) :: Node.t() | nil
  def get_node(%__MODULE__{ets_nodes: ets_nodes} = snapshot, node_id)
      when not is_nil(ets_nodes) and is_binary(node_id) do
    case safe_ets_lookup(ets_nodes, node_id) do
      [{^node_id, %Node{} = node}] -> node
      _ -> Map.get(snapshot.nodes, node_id)
    end
  end

  def get_node(%__MODULE__{nodes: nodes}, node_id) when is_binary(node_id),
    do: Map.get(nodes, node_id)

  @spec edges(t()) :: [Edge.t()]
  def edges(%__MODULE__{ets_edges: ets_edges} = snapshot) when not is_nil(ets_edges) do
    case safe_ets_lookup(ets_edges, :all) do
      [] -> snapshot.edges
      rows -> Enum.map(rows, fn {:all, edge} -> edge end)
    end
  end

  def edges(%__MODULE__{edges: edges}), do: edges

  @spec out_edges(t(), String.t()) :: [Edge.t()]
  def out_edges(%__MODULE__{ets_edges: ets_edges} = snapshot, node_id)
      when not is_nil(ets_edges) and is_binary(node_id) do
    case safe_ets_lookup(ets_edges, {:out, node_id}) do
      [] -> Enum.filter(snapshot.edges, &(&1.from == node_id))
      rows -> Enum.map(rows, fn {{:out, ^node_id}, edge} -> edge end)
    end
  end

  def out_edges(%__MODULE__{edges: edges}, node_id) when is_binary(node_id) do
    Enum.filter(edges, &(&1.from == node_id))
  end

  @spec in_edges(t(), String.t()) :: [Edge.t()]
  def in_edges(%__MODULE__{ets_edges: ets_edges} = snapshot, node_id)
      when not is_nil(ets_edges) and is_binary(node_id) do
    case safe_ets_lookup(ets_edges, {:in, node_id}) do
      [] -> Enum.filter(snapshot.edges, &(&1.to == node_id))
      rows -> Enum.map(rows, fn {{:in, ^node_id}, edge} -> edge end)
    end
  end

  def in_edges(%__MODULE__{edges: edges}, node_id) when is_binary(node_id) do
    Enum.filter(edges, &(&1.to == node_id))
  end

  @spec search_postings(t(), String.t(), SearchIndex.field()) :: [{String.t(), non_neg_integer()}]
  def search_postings(
        %__MODULE__{ets_search_postings: ets_search_postings} = snapshot,
        term,
        field
      )
      when not is_nil(ets_search_postings) and is_binary(term) do
    case safe_ets_lookup(ets_search_postings, {term, field}) do
      [] ->
        fallback_search_postings(snapshot, term, field)

      rows ->
        rows
        |> Enum.map(fn {{^term, ^field}, node_id, tf} -> {node_id, tf} end)
        |> Enum.sort_by(&elem(&1, 0))
    end
  end

  def search_postings(%__MODULE__{} = snapshot, term, field) when is_binary(term) do
    fallback_search_postings(snapshot, term, field)
  end

  @spec search_doc_stats(t(), String.t()) :: map() | nil
  def search_doc_stats(%__MODULE__{ets_search_docs: ets_search_docs} = snapshot, node_id)
      when not is_nil(ets_search_docs) and is_binary(node_id) do
    case safe_ets_lookup(ets_search_docs, node_id) do
      [{^node_id, stats}] -> stats
      _ -> fallback_search_doc_stats(snapshot, node_id)
    end
  end

  def search_doc_stats(%__MODULE__{} = snapshot, node_id) when is_binary(node_id) do
    fallback_search_doc_stats(snapshot, node_id)
  end

  @spec search_body_cache(t(), String.t()) :: String.t() | nil
  def search_body_cache(%__MODULE__{ets_search_bodies: ets_search_bodies} = snapshot, node_id)
      when not is_nil(ets_search_bodies) and is_binary(node_id) do
    case safe_ets_lookup(ets_search_bodies, node_id) do
      [{^node_id, body}] when is_binary(body) -> body
      _ -> fallback_search_body_cache(snapshot, node_id)
    end
  end

  def search_body_cache(%__MODULE__{} = snapshot, node_id) when is_binary(node_id) do
    fallback_search_body_cache(snapshot, node_id)
  end

  @spec search_trigram_terms(t(), String.t()) :: [String.t()]
  def search_trigram_terms(
        %__MODULE__{ets_search_trigrams: ets_search_trigrams} = snapshot,
        trigram
      )
      when not is_nil(ets_search_trigrams) and is_binary(trigram) do
    normalized_trigram = String.downcase(trigram)

    case safe_ets_lookup(ets_search_trigrams, normalized_trigram) do
      [] ->
        fallback_search_trigram_terms(snapshot, normalized_trigram)

      rows ->
        rows
        |> Enum.flat_map(fn
          {^normalized_trigram, term} when is_binary(term) -> [term]
          _other -> []
        end)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  def search_trigram_terms(%__MODULE__{} = snapshot, trigram) when is_binary(trigram) do
    fallback_search_trigram_terms(snapshot, String.downcase(trigram))
  end

  @spec search_corpus_stats(t()) :: map()
  def search_corpus_stats(%__MODULE__{ets_search_docs: ets_search_docs} = snapshot)
      when not is_nil(ets_search_docs) do
    case safe_ets_lookup(ets_search_docs, :__meta__) do
      [{:__meta__, stats}] when is_map(stats) ->
        stats

      _ ->
        fallback_search_corpus_stats(snapshot)
    end
  end

  def search_corpus_stats(%__MODULE__{} = snapshot), do: fallback_search_corpus_stats(snapshot)

  defp fallback_search_postings(
         %__MODULE__{search_index: %SearchIndex{} = search_index},
         term,
         field
       ) do
    search_index.meta
    |> Map.get(:postings, %{})
    |> Map.get({term, field}, [])
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp fallback_search_postings(_snapshot, _term, _field), do: []

  defp fallback_search_doc_stats(
         %__MODULE__{search_index: %SearchIndex{} = search_index},
         node_id
       ) do
    search_index.meta
    |> Map.get(:field_lengths_by_doc, %{})
    |> Map.get(node_id)
  end

  defp fallback_search_doc_stats(_snapshot, _node_id), do: nil

  defp fallback_search_body_cache(
         %__MODULE__{search_index: %SearchIndex{} = search_index},
         node_id
       ) do
    search_index.meta
    |> Map.get(:body_cache, %{})
    |> Map.get(node_id)
  end

  defp fallback_search_body_cache(_snapshot, _node_id), do: nil

  defp fallback_search_trigram_terms(
         %__MODULE__{search_index: %SearchIndex{} = search_index},
         trigram
       ) do
    downcased_trigram = String.downcase(trigram)

    search_index.meta
    |> Map.get(:document_frequencies, %{})
    |> Map.keys()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(fn term ->
      term
      |> Trigram.term_trigrams()
      |> Enum.member?(downcased_trigram)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp fallback_search_trigram_terms(_snapshot, _trigram), do: []

  defp fallback_search_corpus_stats(%__MODULE__{search_index: %SearchIndex{} = search_index}) do
    %{
      document_count: search_index.document_count,
      avg_field_lengths: search_index.avg_field_lengths,
      document_frequencies: Map.get(search_index.meta, :document_frequencies, %{})
    }
  end

  defp fallback_search_corpus_stats(_snapshot) do
    %{
      document_count: 0,
      avg_field_lengths: SearchIndex.default_avg_field_lengths(),
      document_frequencies: %{}
    }
  end

  defp safe_ets_lookup(table, key) do
    :ets.lookup(table, key)
  catch
    :error, :badarg -> []
    :exit, :badarg -> []
  end

  defp safe_ets_tab2list(table) do
    :ets.tab2list(table)
  catch
    :error, :badarg -> []
    :exit, :badarg -> []
  end
end
