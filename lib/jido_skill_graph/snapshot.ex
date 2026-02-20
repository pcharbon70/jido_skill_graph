defmodule JidoSkillGraph.Snapshot do
  @moduledoc """
  Snapshot model and unresolved-link policy contract.
  """

  alias JidoSkillGraph.{Edge, Node}

  @type unresolved_link_policy :: :warn_and_skip | :error | :placeholder

  @policies [:warn_and_skip, :error, :placeholder]

  @enforce_keys [:graph_id, :version, :nodes, :edges, :unresolved_link_policy]
  defstruct [
    :graph,
    :graph_id,
    :manifest,
    :version,
    :unresolved_link_policy,
    :ets_nodes,
    :ets_edges,
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
          ets_nodes: term() | nil,
          ets_edges: term() | nil,
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
          | {:ets_nodes, term() | nil}
          | {:ets_edges, term() | nil}
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
         {:ok, nodes, edges, warnings} <- resolve_edges(nodes, edges, graph_id, policy, []) do
      {:ok,
       %__MODULE__{
         graph: Keyword.get(opts, :graph),
         graph_id: graph_id,
         manifest: Keyword.get(opts, :manifest),
         version: Keyword.get(opts, :version, 0),
         unresolved_link_policy: policy,
         ets_nodes: Keyword.get(opts, :ets_nodes),
         ets_edges: Keyword.get(opts, :ets_edges),
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

  @spec attach_ets(t(), term(), term()) :: t()
  def attach_ets(%__MODULE__{} = snapshot, ets_nodes, ets_edges) do
    %{snapshot | ets_nodes: ets_nodes, ets_edges: ets_edges}
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
