defmodule JidoSkillGraph.MCPToolsTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Loader, Store}
  alias JidoSkillGraph.MCP.Tools

  test "definitions expose expected MCP tools" do
    names = Tools.definitions() |> Enum.map(& &1["name"]) |> Enum.sort()

    assert names == [
             "skills_graph.list",
             "skills_graph.node_links",
             "skills_graph.search",
             "skills_graph.topology"
           ]
  end

  test "skills_graph.list returns loaded graph ids" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, %{"graphs" => ["basic"], "count" => 1}} =
             Tools.call("skills_graph.list", %{}, store: store_name)
  end

  test "skills_graph.topology returns graph summary" do
    {store_name, _loader_name} = load_graph("cycle", "cycle")

    assert {:ok, topology} =
             Tools.call(
               "skills_graph.topology",
               %{"graph_id" => "cycle", "include_nodes" => true, "include_edges" => true},
               store: store_name
             )

    assert topology["graph_id"] == "cycle"
    assert topology["node_count"] == 2
    assert topology["edge_count"] == 2
    assert topology["nodes"] == ["a", "b"]
    assert is_list(topology["edges"])
  end

  test "skills_graph.node_links returns directional links and neighbors" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, payload} =
             Tools.call(
               "skills_graph.node_links",
               %{"graph_id" => "basic", "node_id" => "alpha", "direction" => "out", "hops" => 2},
               store: store_name
             )

    assert payload["direction"] == "out"
    assert length(payload["out_links"]) == 2
    assert payload["in_links"] == []
    assert payload["neighbors"] == ["beta"]
  end

  test "skills_graph.search executes backend search" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, %{"results" => results}} =
             Tools.call(
               "skills_graph.search",
               %{"graph_id" => "basic", "query" => "alpha", "fields" => ["title"]},
               store: store_name
             )

    assert Enum.any?(results, &(&1["id"] == "alpha"))
  end

  test "unknown tool and invalid params return MCP-friendly errors" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:error, %{"error" => %{"code" => "UNKNOWN_TOOL"}}} =
             Tools.call("skills_graph.nope", %{}, store: store_name)

    assert {:error, %{"error" => %{"code" => "INVALID_PARAMS"}}} =
             Tools.call("skills_graph.topology", %{}, store: store_name)
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
