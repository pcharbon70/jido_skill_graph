defmodule JidoSkillGraph.MCPFacadeTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Loader, Store}

  test "new and compatibility facades return equivalent tool and resource schemas" do
    assert JidoSkillGraphMCP.tool_definitions() == JidoSkillGraph.MCP.tool_definitions()

    assert JidoSkillGraphMCP.resource_templates() == JidoSkillGraph.MCP.resource_templates()
  end

  test "new facade delegates tool calls and resource reads" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, %{"graphs" => ["basic"], "count" => 1}} =
             JidoSkillGraphMCP.call_tool("skills_graph.list", %{}, store: store_name)

    assert {:ok, payload} =
             JidoSkillGraphMCP.read_resource("skill://basic/alpha", store: store_name)

    assert payload["graph_id"] == "basic"
    assert payload["node_id"] == "alpha"
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
