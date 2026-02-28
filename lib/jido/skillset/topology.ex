defmodule Jido.Skillset.Topology do
  @moduledoc """
  Builds directed topology graphs from normalized nodes and edges.
  """

  alias Jido.Skillset.Edge

  @spec build(%{required(String.t()) => term()}, [Edge.t()]) :: Graph.t()
  def build(nodes, edges) when is_map(nodes) and is_list(edges) do
    graph = Graph.new(type: :directed)

    graph
    |> add_vertices(nodes)
    |> add_edges(edges)
  end

  defp add_vertices(graph, nodes) do
    nodes
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce(graph, &Graph.add_vertex(&2, &1))
  end

  defp add_edges(graph, edges) do
    edges
    |> Enum.sort_by(&edge_sort_key/1)
    |> Enum.reduce(graph, fn edge, acc ->
      Graph.add_edge(acc, edge.from, edge.to, label: edge.rel)
    end)
  end

  defp edge_sort_key(%Edge{} = edge) do
    {edge.from, edge.to, edge.rel, edge.label || ""}
  end
end
