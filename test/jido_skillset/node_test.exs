defmodule Jido.Skillset.NodeTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.Node

  test "derive_id/2 is stable for same path and root" do
    path = "/repo/skills/therapy/SKILL.md"
    root = "/repo/skills"

    assert Node.derive_id(path, root: root) == "therapy"
    assert Node.derive_id(path, root: root) == "therapy"
  end

  test "derive_id/2 treats SKILL.md and skill.md as the folder identity" do
    root = "/repo/skills"

    assert Node.derive_id("/repo/skills/cbt/SKILL.md", root: root) == "cbt"
    assert Node.derive_id("/repo/skills/cbt/skill.md", root: root) == "cbt"
  end

  test "derive_id/2 uses slug override" do
    assert Node.derive_id("/repo/skills/cbt/SKILL.md", slug: "Cognitive Behavioral") ==
             "cognitive-behavioral"
  end

  test "new/1 returns node with derived id" do
    assert {:ok, node} =
             Node.new(
               graph_id: "knowledge-work",
               path: "/repo/skills/discovery-retrieval/SKILL.md",
               root: "/repo/skills"
             )

    assert node.id == "discovery-retrieval"
    assert node.graph_id == "knowledge-work"
  end
end
