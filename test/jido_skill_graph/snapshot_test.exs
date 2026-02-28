defmodule JidoSkillGraph.SnapshotTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Edge, Node, SearchIndex, Snapshot}

  test "new/1 with warn_and_skip drops unresolved edges and emits warnings" do
    node = Node.placeholder("graph", "a")
    {:ok, edge} = Edge.new(from: "a", to: "missing", rel: :related)

    assert {:ok, snapshot} =
             Snapshot.new(
               graph_id: "graph",
               nodes: [node],
               edges: [edge],
               unresolved_link_policy: :warn_and_skip
             )

    assert snapshot.edges == []
    assert length(snapshot.warnings) == 1
  end

  test "new/1 with error policy returns unresolved edge error" do
    node = Node.placeholder("graph", "a")
    {:ok, edge} = Edge.new(from: "a", to: "missing", rel: :related)

    assert {:error, {:unresolved_edge, _edge, ["missing"]}} =
             Snapshot.new(
               graph_id: "graph",
               nodes: [node],
               edges: [edge],
               unresolved_link_policy: :error
             )
  end

  test "new/1 with placeholder policy creates missing nodes" do
    node = Node.placeholder("graph", "a")
    {:ok, edge} = Edge.new(from: "a", to: "missing", rel: :related)

    assert {:ok, snapshot} =
             Snapshot.new(
               graph_id: "graph",
               nodes: [node],
               edges: [edge],
               unresolved_link_policy: :placeholder
             )

    assert Map.has_key?(snapshot.nodes, "missing")
    assert snapshot.edges == [edge]
    assert length(snapshot.warnings) == 1
  end

  test "helper accessors read from ETS when available" do
    node_a = Node.placeholder("graph", "a")
    node_b = Node.placeholder("graph", "b")
    {:ok, edge} = Edge.new(from: "a", to: "b", rel: :related)

    {:ok, snapshot} =
      Snapshot.new(
        graph_id: "graph",
        nodes: [node_a, node_b],
        edges: [edge],
        unresolved_link_policy: :warn_and_skip
      )

    ets_nodes = :ets.new(__MODULE__, [:set, :protected])
    ets_edges = :ets.new(__MODULE__, [:duplicate_bag, :protected])
    ets_search_postings = :ets.new(__MODULE__, [:duplicate_bag, :protected])
    ets_search_docs = :ets.new(__MODULE__, [:set, :protected])
    ets_search_trigrams = :ets.new(__MODULE__, [:duplicate_bag, :protected])

    true =
      :ets.insert(ets_nodes, [{"a", node_a}, {"b", node_b}])

    true =
      :ets.insert(ets_edges, [{:all, edge}, {{:out, "a"}, edge}, {{:in, "b"}, edge}])

    true = :ets.insert(ets_search_postings, [{{"alpha", :id}, "a", 1}])
    true = :ets.insert(ets_search_docs, [{"a", %{id: 1, title: 1, tags: 0, body: 2}}])
    true = :ets.insert(ets_search_docs, [{:__meta__, %{document_count: 2}}])
    true = :ets.insert(ets_search_trigrams, [{:__meta__, %{enabled: false}}])

    indexed =
      Snapshot.attach_ets(
        snapshot,
        ets_nodes,
        ets_edges,
        ets_search_postings,
        ets_search_docs,
        ets_search_trigrams
      )

    assert Snapshot.node_ids(indexed) |> Enum.sort() == ["a", "b"]
    assert %Node{id: "a"} = Snapshot.get_node(indexed, "a")
    assert Snapshot.edges(indexed) == [edge]
    assert Snapshot.out_edges(indexed, "a") == [edge]
    assert Snapshot.in_edges(indexed, "b") == [edge]
    assert Snapshot.search_postings(indexed, "alpha", :id) == [{"a", 1}]
    assert Snapshot.search_doc_stats(indexed, "a") == %{id: 1, title: 1, tags: 0, body: 2}
    assert Snapshot.search_corpus_stats(indexed) == %{document_count: 2}
  end

  test "new/1 accepts search index metadata" do
    node = Node.placeholder("graph", "a")

    assert {:ok, search_index} =
             SearchIndex.new(
               build_version: 1,
               document_count: 1,
               avg_field_lengths: %{id: 1.0, title: 2.0, tags: 3.0, body: 4.0}
             )

    assert {:ok, snapshot} =
             Snapshot.new(
               graph_id: "graph",
               nodes: [node],
               edges: [],
               unresolved_link_policy: :warn_and_skip,
               search_index: search_index
             )

    assert snapshot.search_index == search_index
  end

  test "new/1 rejects invalid search index shape" do
    node = Node.placeholder("graph", "a")

    assert {:error, {:invalid_search_index, :invalid_shape}} =
             Snapshot.new(
               graph_id: "graph",
               nodes: [node],
               edges: [],
               unresolved_link_policy: :warn_and_skip,
               search_index: %{invalid: true}
             )
  end
end
