defmodule Jido.Skillset.QueryTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.{Loader, Store}

  test "list_graphs/1 is empty when no snapshot is loaded" do
    store_name = unique_name(:store)
    start_supervised!({Store, name: store_name})

    assert Jido.Skillset.list_graphs(store: store_name) == []
    assert {:error, :graph_not_loaded} = Jido.Skillset.topology("basic", store: store_name)
  end

  test "topology/2 returns summary and optional topology details" do
    {store_name, _loader_name} = load_graph("cycle", "cycle")

    assert {:ok, topology} = Jido.Skillset.topology("cycle", store: store_name)
    assert topology.graph_id == "cycle"
    assert topology.node_count == 2
    assert topology.edge_count == 2
    assert topology.cyclic?

    assert {:ok, details} =
             Jido.Skillset.topology("cycle",
               store: store_name,
               include_nodes: true,
               include_edges: true
             )

    assert details.nodes == ["a", "b"]
    assert length(details.edges) == 2
  end

  test "node metadata and body reads are available through facade" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, nodes} = Jido.Skillset.list_nodes("basic", store: store_name)
    assert nodes |> Enum.map(& &1.id) |> Enum.sort() == ["alpha", "beta"]

    assert {:ok, [tagged]} = Jido.Skillset.list_nodes("basic", store: store_name, tags: ["core"])
    assert tagged.id == "alpha"

    assert {:ok, alpha_meta} = Jido.Skillset.get_node_meta("basic", "alpha", store: store_name)
    assert alpha_meta.title == "Alpha"

    assert {:ok, body} = Jido.Skillset.read_node_body("basic", "alpha", store: store_name)
    assert String.contains?(body, "Alpha references")

    assert {:ok, payload} =
             Jido.Skillset.read_node_body("basic", "alpha",
               store: store_name,
               with_frontmatter: true
             )

    assert payload.frontmatter["title"] == "Alpha"

    assert {:error, {:unknown_node, "missing"}} =
             Jido.Skillset.get_node_meta("basic", "missing", store: store_name)
  end

  test "link traversal APIs support rel filtering and neighbor hops" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, out_links} = Jido.Skillset.out_links("basic", "alpha", store: store_name)
    assert length(out_links) == 2

    assert {:ok, prereq_links} =
             Jido.Skillset.out_links("basic", "alpha", store: store_name, rel: :prereq)

    assert Enum.all?(prereq_links, &(&1.rel == :prereq))

    assert {:ok, in_links} = Jido.Skillset.in_links("basic", "beta", store: store_name)
    assert length(in_links) == 2

    assert {:ok, ["beta"]} =
             Jido.Skillset.neighbors("basic", "alpha",
               store: store_name,
               direction: :out,
               hops: 2
             )

    assert {:ok, ["alpha"]} =
             Jido.Skillset.neighbors("basic", "beta", store: store_name, direction: :in, hops: 1)

    assert {:error, {:invalid_relation_filter, :depends_on}} =
             Jido.Skillset.out_links("basic", "alpha", store: store_name, rel: :depends_on)
  end

  defp load_graph(fixture, graph_id) do
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: false,
       builder_opts: [root: fixture_path(fixture), graph_id: graph_id]}
    )

    assert :ok = Loader.reload(loader_name)
    {store_name, loader_name}
  end

  defp unique_name(kind), do: {:global, {__MODULE__, kind, make_ref()}}

  defp fixture_path(name) do
    Path.expand("../fixtures/phase4/#{name}", __DIR__)
  end
end
