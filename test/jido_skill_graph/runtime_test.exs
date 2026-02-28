defmodule JidoSkillGraph.RuntimeTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Builder, Loader, Snapshot, Store}

  test "store publishes snapshots atomically and keeps monotonic version" do
    store_name = unique_name(:store)
    start_supervised!({Store, name: store_name})

    assert Store.current_snapshot(store_name) == nil
    assert %{version: 0} = Store.metadata(store_name)

    {:ok, snapshot_v5} =
      Builder.build(root: fixture_path("basic"), graph_id: "runtime", version: 5)

    assert {:ok, committed_v5} = Store.swap_snapshot(store_name, snapshot_v5)
    assert committed_v5.version == 5

    {:ok, snapshot_v3} =
      Builder.build(root: fixture_path("basic"), graph_id: "runtime", version: 3)

    assert {:ok, committed_v6} = Store.swap_snapshot(store_name, snapshot_v3)
    assert committed_v6.version == 6

    assert Store.current_snapshot(store_name).version == 6
    assert %{version: 6} = Store.metadata(store_name)
  end

  test "store publishes snapshots with ETS node, edge, and search indexes" do
    store_name = unique_name(:store)
    start_supervised!({Store, name: store_name})

    {:ok, snapshot} =
      Builder.build(root: fixture_path("basic"), graph_id: "runtime", version: 1)

    assert {:ok, committed} = Store.swap_snapshot(store_name, snapshot)
    assert is_reference(committed.ets_nodes)
    assert is_reference(committed.ets_edges)
    assert is_reference(committed.ets_search_postings)
    assert is_reference(committed.ets_search_docs)
    assert is_reference(committed.ets_search_trigrams)
    assert is_reference(committed.ets_search_bodies)

    assert %JidoSkillGraph.Node{id: "alpha"} = Snapshot.get_node(committed, "alpha")
    assert length(Snapshot.out_edges(committed, "alpha")) == 2
    assert length(Snapshot.in_edges(committed, "beta")) == 2
    assert Snapshot.search_postings(committed, "alpha", :id) == [{"alpha", 1}]
    assert Snapshot.search_doc_stats(committed, "alpha").body > 0
    assert Snapshot.search_corpus_stats(committed).document_count == 2
    assert is_binary(Snapshot.search_body_cache(committed, "alpha"))
    assert Snapshot.search_body_cache(committed, "missing") == nil
  end

  test "loader reload swaps snapshots and bumps runtime version" do
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: false,
       builder_opts: [root: fixture_path("basic"), graph_id: "runtime"]}
    )

    assert :ok = Loader.reload(loader_name)
    first = Store.current_snapshot(store_name)
    assert %Snapshot{} = first
    assert first.version == 1

    assert :ok = Loader.reload(loader_name)
    second = Store.current_snapshot(store_name)
    assert second.version == 2

    assert %{version: 2, last_error: nil} = Loader.status(loader_name)
  end

  test "loader failure does not replace current snapshot" do
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: false,
       builder_opts: [root: fixture_path("basic"), graph_id: "runtime"]}
    )

    assert :ok = Loader.reload(loader_name)
    current = Store.current_snapshot(store_name)

    assert {:error, {:build_failed, {:invalid_frontmatter, _path, _reason}}} =
             Loader.reload(loader_name,
               root: fixture_path("malformed_frontmatter"),
               graph_id: "runtime"
             )

    after_failure = Store.current_snapshot(store_name)

    assert current.version == after_failure.version
    assert current.stats.snapshot_checksum == after_failure.stats.snapshot_checksum

    assert %{last_error: {:build_failed, {:invalid_frontmatter, _path, _reason}}} =
             Loader.status(loader_name)
  end

  test "facade supervisor wiring connects configured store and loader names" do
    graph_name = unique_name(:graph)
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!(
      {JidoSkillGraph,
       name: graph_name,
       store: [name: store_name],
       loader: [
         name: loader_name,
         load_on_start: false,
         builder_opts: [root: fixture_path("basic"), graph_id: "runtime"]
       ]}
    )

    assert :ok = JidoSkillGraph.reload(loader_name)
    assert %Snapshot{} = JidoSkillGraph.current_snapshot(store_name)
  end

  test "concurrent reads continue while snapshot is swapped" do
    store_name = unique_name(:store)
    start_supervised!({Store, name: store_name})

    {:ok, snapshot_one} =
      Builder.build(root: fixture_path("basic"), graph_id: "runtime", version: 1)

    {:ok, snapshot_two} =
      Builder.build(root: fixture_path("cycle"), graph_id: "runtime", version: 2)

    assert {:ok, _} = Store.swap_snapshot(store_name, snapshot_one)

    reader =
      Task.async(fn ->
        Enum.each(1..500, fn _ ->
          _ = Store.current_snapshot(store_name)
        end)
      end)

    assert {:ok, _} = Store.swap_snapshot(store_name, snapshot_two)
    assert :ok == Task.await(reader)
    assert Store.current_snapshot(store_name).version == 2
  end

  defp unique_name(kind), do: {:global, {__MODULE__, kind, make_ref()}}

  defp fixture_path(name) do
    Path.expand("../fixtures/phase4/#{name}", __DIR__)
  end
end
