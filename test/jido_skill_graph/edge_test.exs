defmodule JidoSkillGraph.EdgeTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.Edge

  test "new/1 accepts taxonomy relation atoms" do
    assert {:ok, edge} = Edge.new(from: "a", to: "b", rel: :prereq)
    assert edge.rel == :prereq
  end

  test "new/1 accepts taxonomy relation strings" do
    assert {:ok, edge} = Edge.new(from: "a", to: "b", rel: "extends")
    assert edge.rel == :extends
  end

  test "new/1 rejects invalid relations" do
    assert {:error, {:invalid_relation, "depends_on"}} =
             Edge.new(from: "a", to: "b", rel: "depends_on")
  end
end
