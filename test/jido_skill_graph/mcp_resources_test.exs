defmodule JidoSkillGraph.MCPResourcesTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Loader, Store}
  alias JidoSkillGraph.MCP
  alias JidoSkillGraph.MCP.Resources, as: CompatResources
  alias JidoSkillGraphMCP.Resources

  test "templates define skill URI resource" do
    templates = Resources.templates()
    assert [%{"uriTemplate" => "skill://{graph_id}/{node_id}"}] = templates

    assert CompatResources.templates() == templates
    assert MCP.resource_templates() == templates
  end

  test "parse_uri supports nested node ids" do
    assert {:ok, %{graph_id: "basic", node_id: "selected/a"}} =
             Resources.parse_uri("skill://basic/selected/a")

    assert {:error, :unsupported_scheme} = Resources.parse_uri("https://example.com")
    assert {:error, :invalid_skill_uri} = Resources.parse_uri("skill://basic")
  end

  test "read returns markdown body for skill URI" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, payload} = Resources.read("skill://basic/alpha", store: store_name)
    assert payload["mimeType"] == "text/markdown"
    assert String.contains?(payload["text"], "Alpha references")

    assert {:ok, compat_payload} =
             CompatResources.read("skill://basic/alpha", store: store_name)

    assert {:ok, facade_payload} =
             MCP.read_resource("skill://basic/alpha", store: store_name)

    assert compat_payload == payload
    assert facade_payload == payload
  end

  test "read returns MCP-friendly errors for unknown resource" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:error, %{"error" => %{"code" => "UNKNOWN_NODE"}}} =
             Resources.read("skill://basic/missing", store: store_name)
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
