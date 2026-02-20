defmodule ElixirProgrammingSkillsDemo do
  @moduledoc false

  @graph_name ElixirProgrammingSkillsDemo.Graph
  @store_name ElixirProgrammingSkillsDemo.Store
  @loader_name ElixirProgrammingSkillsDemo.Loader

  def run do
    root = Path.expand("skills", __DIR__)

    {:ok, _pid} =
      JidoSkillGraph.start_link(
        name: @graph_name,
        store: [name: @store_name],
        loader: [name: @loader_name, load_on_start: false, builder_opts: [root: root]]
      )

    :ok = JidoSkillGraph.reload(@loader_name)

    graph_id =
      JidoSkillGraph.list_graphs(store: @store_name)
      |> List.first()

    IO.puts("Loaded graph: #{graph_id}")

    {:ok, topology} =
      JidoSkillGraph.topology(graph_id, store: @store_name, include_nodes: true, include_edges: true)

    IO.puts("Nodes: #{topology.node_count}")
    IO.puts("Edges: #{topology.edge_count}")
    IO.inspect(Map.take(topology, [:graph_id, :node_count, :edge_count, :cyclic?]))

    {:ok, path_nodes} = JidoSkillGraph.list_nodes(graph_id, store: @store_name, tags: ["path"])
    IO.puts("Path nodes: #{Enum.map_join(path_nodes, ", ", & &1.id)}")

    {:ok, neighbors} =
      JidoSkillGraph.neighbors(graph_id, "elixir-learning-path",
        store: @store_name,
        hops: 1,
        direction: :out
      )

    IO.inspect(%{entrypoint_neighbors: neighbors})

    {:ok, results} =
      JidoSkillGraph.search(graph_id, "pattern match function", store: @store_name, limit: 3)

    IO.inspect(results)
  end
end

ElixirProgrammingSkillsDemo.run()
