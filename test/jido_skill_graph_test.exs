defmodule JidoSkillGraphTest do
  use ExUnit.Case, async: true

  test "build/1 returns a pure-mode snapshot skeleton" do
    assert {:ok, snapshot} = JidoSkillGraph.build(root: "/tmp/skills")
    assert snapshot.mode == :pure
    assert snapshot.version == 0
    assert snapshot.nodes == []
    assert snapshot.edges == []
  end
end
