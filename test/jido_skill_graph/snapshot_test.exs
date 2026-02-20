defmodule JidoSkillGraph.SnapshotTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.{Edge, Node, Snapshot}

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

    true =
      :ets.insert(ets_nodes, [{"a", node_a}, {"b", node_b}])

    true =
      :ets.insert(ets_edges, [{:all, edge}, {{:out, "a"}, edge}, {{:in, "b"}, edge}])

    indexed = Snapshot.attach_ets(snapshot, ets_nodes, ets_edges)

    assert Snapshot.node_ids(indexed) |> Enum.sort() == ["a", "b"]
    assert %Node{id: "a"} = Snapshot.get_node(indexed, "a")
    assert Snapshot.edges(indexed) == [edge]
    assert Snapshot.out_edges(indexed, "a") == [edge]
    assert Snapshot.in_edges(indexed, "b") == [edge]
  end
end
