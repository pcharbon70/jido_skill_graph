defmodule JidoSkillGraph.JidoAIAdapterTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{JidoAIAdapter, Loader, Store}

  test "list_skill_candidates returns metadata and supports tag filtering" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, candidates} = JidoAIAdapter.list_skill_candidates("basic", store: store_name)
    assert candidates |> Enum.map(& &1.id) |> Enum.sort() == ["alpha", "beta"]

    assert {:ok, [core]} =
             JidoAIAdapter.list_skill_candidates("basic", store: store_name, tags: ["core"])

    assert core.id == "alpha"
  end

  test "read_skill returns body content and optional frontmatter payload" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, body} = JidoAIAdapter.read_skill("basic", "alpha", store: store_name, trim: true)
    assert String.contains?(body, "Alpha references")

    assert {:ok, payload} =
             JidoAIAdapter.read_skill("basic", "alpha",
               store: store_name,
               with_frontmatter: true
             )

    assert payload.frontmatter["title"] == "Alpha"
  end

  test "related_skills and search_skills delegate traversal and search APIs" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, ["beta"]} = JidoAIAdapter.related_skills("basic", "alpha", store: store_name)

    assert {:ok, results} =
             JidoAIAdapter.search_skills("basic", "alpha", store: store_name, fields: ["title"])

    assert Enum.any?(results, &(&1.id == "alpha"))
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
