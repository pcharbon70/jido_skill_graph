defmodule JidoSkillGraph.SearchTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Loader, SearchBackend, Store}

  defmodule StubBackend do
    @behaviour SearchBackend

    @impl true
    def search(_snapshot, _graph_id, query, _opts) do
      {:ok, [%{id: "stub", score: 1, matches: [:id], title: query}]}
    end
  end

  test "search/3 returns title/tag/body matches from basic backend" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, results} = JidoSkillGraph.search("basic", "Alpha", store: store_name)
    assert [%{id: "alpha"} | _] = results

    assert {:ok, tag_results} =
             JidoSkillGraph.search("basic", "core", store: store_name, fields: [:tags])

    assert Enum.any?(tag_results, &(&1.id == "alpha" and :tags in &1.matches))

    assert {:ok, body_results} =
             JidoSkillGraph.search("basic", "references", store: store_name, fields: [:body])

    assert Enum.any?(body_results, &(&1.id == "alpha" and :body in &1.matches))
  end

  test "search/3 supports limit and deterministic ordering" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, one} = JidoSkillGraph.search("basic", "a", store: store_name, limit: 1)
    assert length(one) == 1

    assert {:ok, all} = JidoSkillGraph.search("basic", "a", store: store_name)
    assert length(all) >= length(one)
  end

  test "search/3 allows pluggable backend" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, [%{id: "stub", title: "custom query"}]} =
             JidoSkillGraph.search("basic", "custom query",
               store: store_name,
               search_backend: StubBackend
             )
  end

  test "search/3 validates backend module and graph identity" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:error, {:invalid_search_backend, :not_a_module}} =
             JidoSkillGraph.search("basic", "x", store: store_name, search_backend: :not_a_module)

    assert {:error, {:unknown_graph, "other"}} =
             JidoSkillGraph.search("other", "x", store: store_name)
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
