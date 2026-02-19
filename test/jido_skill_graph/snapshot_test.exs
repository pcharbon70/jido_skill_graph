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
end
