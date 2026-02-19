defmodule JidoSkillGraphTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.Snapshot

  test "build/1 returns a snapshot struct" do
    assert {:ok, %Snapshot{} = snapshot} = JidoSkillGraph.build(graph_id: "knowledge-work")

    assert snapshot.graph_id == "knowledge-work"
    assert snapshot.version == 0
    assert snapshot.nodes == %{}
    assert snapshot.edges == []
    assert snapshot.unresolved_link_policy == :warn_and_skip
  end

  test "build/1 validates unresolved link policy" do
    assert {:error, {:invalid_unresolved_link_policy, :drop}} =
             JidoSkillGraph.build(unresolved_link_policy: :drop)
  end
end
