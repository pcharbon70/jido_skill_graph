defmodule GardeningSkillsApp do
  @moduledoc false

  @graph_name GardeningSkillsApp.Graph
  @store_name GardeningSkillsApp.Store
  @loader_name GardeningSkillsApp.Loader

  def run do
    root = Path.expand("skills", __DIR__)

    {:ok, _pid} =
      Jido.Skillset.start_link(
        name: @graph_name,
        store: [name: @store_name],
        loader: [name: @loader_name, load_on_start: false, builder_opts: [root: root]]
      )

    :ok = Jido.Skillset.reload(@loader_name)

    graph_id =
      Jido.Skillset.list_graphs(store: @store_name)
      |> List.first()

    print_header("Loaded Graph")
    IO.inspect(%{graph_id: graph_id, root: root})

    print_header("Topology")

    {:ok, topology} =
      Jido.Skillset.topology(graph_id,
        store: @store_name,
        include_nodes: true,
        include_edges: true
      )

    IO.inspect(Map.take(topology, [:graph_id, :version, :node_count, :edge_count, :cyclic?]))

    print_header("Query: list_nodes/2")
    {:ok, nodes} = Jido.Skillset.list_nodes(graph_id, store: @store_name, sort_by: :title)
    IO.inspect(Enum.map(nodes, &Map.take(&1, [:id, :title, :tags])))

    print_header("Query: list_nodes/2 filtered by tags")
    {:ok, basics} = Jido.Skillset.list_nodes(graph_id, store: @store_name, tags: ["basics"])
    IO.inspect(Enum.map(basics, & &1.id))

    print_header("Query: out_links/3 for garden-basics")
    {:ok, out_links} = Jido.Skillset.out_links(graph_id, "garden-basics", store: @store_name)
    IO.inspect(Enum.map(out_links, &%{from: &1.from, to: &1.to, rel: &1.rel}))

    print_header("Query: neighbors/3 from garden-basics (2 hops)")

    {:ok, neighbors} =
      Jido.Skillset.neighbors(graph_id, "garden-basics",
        store: @store_name,
        direction: :out,
        hops: 2
      )

    IO.inspect(neighbors)

    print_header("Query: search/3")
    {:ok, search_results} = Jido.Skillset.search(graph_id, "soil compost", store: @store_name, limit: 3)
    IO.inspect(Enum.map(search_results, &Map.take(&1, [:id, :score, :matches])))

    print_header("Query: read_node_body/3 with frontmatter")

    {:ok, payload} =
      Jido.Skillset.read_node_body(graph_id, "compost",
        store: @store_name,
        with_frontmatter: true,
        trim: true
      )

    IO.inspect(Map.take(payload, [:frontmatter, :body]))

    :ok
  end

  defp print_header(label) do
    IO.puts("")
    IO.puts("=== #{label} ===")
  end
end

GardeningSkillsApp.run()
