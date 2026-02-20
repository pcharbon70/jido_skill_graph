defmodule JidoSkillGraph.Query do
  @moduledoc """
  Query operations over immutable `JidoSkillGraph.Snapshot` structs.
  """

  alias JidoSkillGraph.{Edge, SearchBackend, SkillFile, Snapshot}
  alias JidoSkillGraph.SearchBackend.Basic, as: BasicSearch

  @type query_error ::
          :graph_not_loaded
          | {:unknown_graph, String.t()}
          | {:unknown_node, String.t()}
          | {:invalid_relation_filter, term()}
          | {:invalid_search_backend, term()}
          | :body_unavailable
          | term()

  @type edge_opts :: {:rel, Edge.relation() | String.t() | [Edge.relation() | String.t()]}

  @spec list_graphs(Snapshot.t() | nil) :: [String.t()]
  def list_graphs(nil), do: []
  def list_graphs(%Snapshot{graph_id: graph_id}), do: [graph_id]

  @spec topology(Snapshot.t() | nil, String.t(), keyword()) ::
          {:ok, map()} | {:error, query_error()}
  def topology(snapshot, graph_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id) do
      graph = snapshot.graph

      base = %{
        graph_id: snapshot.graph_id,
        version: snapshot.version,
        node_count: snapshot |> Snapshot.node_ids() |> length(),
        edge_count: snapshot |> Snapshot.edges() |> length(),
        warning_count: length(snapshot.warnings),
        cyclic?: graph && Graph.is_cyclic?(graph),
        stats: snapshot.stats
      }

      payload =
        base
        |> maybe_include_nodes(opts, snapshot)
        |> maybe_include_edges(opts, snapshot)

      {:ok, payload}
    end
  end

  @spec list_nodes(Snapshot.t() | nil, String.t(), keyword()) ::
          {:ok, [map()]} | {:error, query_error()}
  def list_nodes(snapshot, graph_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id) do
      nodes =
        snapshot
        |> Snapshot.nodes()
        |> Enum.map(&node_meta/1)
        |> filter_nodes(opts)
        |> sort_nodes(opts)

      {:ok, nodes}
    end
  end

  @spec get_node_meta(Snapshot.t() | nil, String.t(), String.t()) ::
          {:ok, map()} | {:error, query_error()}
  def get_node_meta(snapshot, graph_id, node_id) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, node} <- ensure_node(snapshot, node_id) do
      {:ok, node_meta(node)}
    end
  end

  @spec read_node_body(Snapshot.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, String.t() | map()} | {:error, query_error()}
  def read_node_body(snapshot, graph_id, node_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, node} <- ensure_node(snapshot, node_id),
         {:ok, body_ref} <- ensure_body_ref(node.body_ref),
         {:ok, %SkillFile{} = document} <- SkillFile.parse(body_ref) do
      body =
        if Keyword.get(opts, :trim, false), do: String.trim(document.body), else: document.body

      if Keyword.get(opts, :with_frontmatter, false) do
        {:ok, %{body: body, frontmatter: document.frontmatter, path: document.path}}
      else
        {:ok, body}
      end
    end
  end

  @spec out_links(Snapshot.t() | nil, String.t(), String.t(), [edge_opts()]) ::
          {:ok, [Edge.t()]} | {:error, query_error()}
  def out_links(snapshot, graph_id, node_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, _node} <- ensure_node(snapshot, node_id),
         {:ok, rel_filter} <- relation_filter(opts) do
      links =
        snapshot
        |> Snapshot.out_edges(node_id)
        |> filter_edges_by_rel(rel_filter)

      {:ok, links}
    end
  end

  @spec in_links(Snapshot.t() | nil, String.t(), String.t(), [edge_opts()]) ::
          {:ok, [Edge.t()]} | {:error, query_error()}
  def in_links(snapshot, graph_id, node_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, _node} <- ensure_node(snapshot, node_id),
         {:ok, rel_filter} <- relation_filter(opts) do
      links =
        snapshot
        |> Snapshot.in_edges(node_id)
        |> filter_edges_by_rel(rel_filter)

      {:ok, links}
    end
  end

  @spec neighbors(Snapshot.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, query_error()}
  def neighbors(snapshot, graph_id, node_id, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, _node} <- ensure_node(snapshot, node_id),
         {:ok, rel_filter} <- relation_filter(opts),
         {:ok, direction} <- direction_filter(opts) do
      hops = normalize_hops(Keyword.get(opts, :hops, 1))

      edges = snapshot |> Snapshot.edges() |> filter_edges_by_rel(rel_filter)

      neighbor_ids =
        edges
        |> traverse_neighbors(node_id, hops, direction)
        |> MapSet.delete(node_id)
        |> MapSet.to_list()
        |> Enum.sort()

      {:ok, neighbor_ids}
    end
  end

  @spec search(Snapshot.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, [SearchBackend.result()]} | {:error, query_error()}
  def search(snapshot, graph_id, query, opts \\ []) do
    with {:ok, snapshot} <- ensure_graph(snapshot, graph_id),
         {:ok, backend} <- search_backend(opts),
         do: backend.search(snapshot, graph_id, query, opts)
  end

  defp ensure_graph(nil, _graph_id), do: {:error, :graph_not_loaded}

  defp ensure_graph(%Snapshot{graph_id: graph_id} = snapshot, graph_id), do: {:ok, snapshot}

  defp ensure_graph(%Snapshot{}, graph_id), do: {:error, {:unknown_graph, graph_id}}

  defp ensure_node(%Snapshot{} = snapshot, node_id) do
    case Snapshot.get_node(snapshot, node_id) do
      nil -> {:error, {:unknown_node, node_id}}
      node -> {:ok, node}
    end
  end

  defp ensure_body_ref(path) when is_binary(path) and path != "", do: {:ok, path}
  defp ensure_body_ref(_body_ref), do: {:error, :body_unavailable}

  defp node_meta(node) do
    %{
      id: node.id,
      title: node.title,
      tags: node.tags,
      path: node.path,
      checksum: node.checksum,
      placeholder?: node.placeholder?,
      graph_id: node.graph_id
    }
  end

  defp maybe_include_nodes(payload, opts, snapshot) do
    if Keyword.get(opts, :include_nodes, false) do
      Map.put(payload, :nodes, snapshot |> Snapshot.node_ids() |> Enum.sort())
    else
      payload
    end
  end

  defp maybe_include_edges(payload, opts, snapshot) do
    if Keyword.get(opts, :include_edges, false) do
      edges =
        snapshot
        |> Snapshot.edges()
        |> Enum.sort_by(&{&1.from, &1.to, &1.rel})
        |> Enum.map(fn edge ->
          %{from: edge.from, to: edge.to, rel: edge.rel, label: edge.label}
        end)

      Map.put(payload, :edges, edges)
    else
      payload
    end
  end

  defp filter_nodes(nodes, opts) do
    case Keyword.get(opts, :tags) do
      nil ->
        nodes

      [] ->
        nodes

      tags when is_list(tags) ->
        tag_set = tags |> Enum.filter(&is_binary/1) |> MapSet.new()

        Enum.filter(nodes, fn node ->
          node.tags
          |> MapSet.new()
          |> MapSet.intersection(tag_set)
          |> MapSet.size() > 0
        end)

      _ ->
        nodes
    end
  end

  defp sort_nodes(nodes, opts) do
    case Keyword.get(opts, :sort_by, :id) do
      :title -> Enum.sort_by(nodes, &{&1.title || "", &1.id})
      _ -> Enum.sort_by(nodes, & &1.id)
    end
  end

  defp relation_filter(opts) do
    case Keyword.get(opts, :rel) do
      nil -> {:ok, :all}
      rel when is_list(rel) -> normalize_rel_list(rel)
      rel -> normalize_rel_list([rel])
    end
  end

  defp normalize_rel_list(values) do
    values
    |> Enum.reduce_while({:ok, MapSet.new()}, fn value, {:ok, acc} ->
      case Edge.normalize_relation(value) do
        {:ok, relation} -> {:cont, {:ok, MapSet.put(acc, relation)}}
        {:error, _reason} -> {:halt, {:error, {:invalid_relation_filter, value}}}
      end
    end)
  end

  defp filter_edges_by_rel(edges, :all), do: edges

  defp filter_edges_by_rel(edges, %MapSet{} = rel_filter) do
    Enum.filter(edges, &MapSet.member?(rel_filter, &1.rel))
  end

  defp direction_filter(opts) do
    case Keyword.get(opts, :direction, :both) do
      dir when dir in [:out, :in, :both] -> {:ok, dir}
      other -> {:error, {:invalid_direction, other}}
    end
  end

  defp search_backend(opts) do
    backend = Keyword.get(opts, :search_backend, BasicSearch)

    if is_atom(backend) and Code.ensure_loaded?(backend) and
         function_exported?(backend, :search, 4) do
      {:ok, backend}
    else
      {:error, {:invalid_search_backend, backend}}
    end
  end

  defp normalize_hops(hops) when is_integer(hops) and hops >= 1, do: hops
  defp normalize_hops(_hops), do: 1

  defp traverse_neighbors(edges, root, hops, direction) do
    adjacency = build_adjacency(edges, direction)

    {_frontier, visited} =
      Enum.reduce(1..hops, {MapSet.new([root]), MapSet.new([root])}, fn _, {frontier, visited} ->
        next_frontier =
          frontier
          |> Enum.flat_map(&Map.get(adjacency, &1, []))
          |> MapSet.new()

        {next_frontier, MapSet.union(visited, next_frontier)}
      end)

    visited
  end

  defp build_adjacency(edges, :out),
    do: reduce_adjacency(edges, fn edge -> [{edge.from, edge.to}] end)

  defp build_adjacency(edges, :in),
    do: reduce_adjacency(edges, fn edge -> [{edge.to, edge.from}] end)

  defp build_adjacency(edges, :both) do
    reduce_adjacency(edges, fn edge -> [{edge.from, edge.to}, {edge.to, edge.from}] end)
  end

  defp reduce_adjacency(edges, mapping_fun) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      edge
      |> mapping_fun.()
      |> Enum.reduce(acc, fn {from, to}, inner_acc ->
        Map.update(inner_acc, from, [to], &[to | &1])
      end)
    end)
  end
end
