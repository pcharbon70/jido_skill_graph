defmodule JidoSkillGraphTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.Snapshot

  test "build/1 returns a snapshot struct" do
    assert {:ok, %Snapshot{} = snapshot} =
             JidoSkillGraph.build(root: fixture_path("basic"), graph_id: "knowledge-work")

    assert snapshot.graph_id == "knowledge-work"
    assert snapshot.version == 0
    assert Map.keys(snapshot.nodes) |> Enum.sort() == ["alpha", "beta"]
    assert Enum.any?(snapshot.edges, &(&1.from == "alpha" and &1.to == "beta"))
    assert snapshot.unresolved_link_policy == :warn_and_skip
  end

  test "build/1 validates unresolved link policy" do
    assert {:error, {:invalid_unresolved_link_policy, :drop}} =
             JidoSkillGraph.build(root: fixture_path("basic"), unresolved_link_policy: :drop)
  end

  defp fixture_path(name) do
    Path.expand("fixtures/phase4/#{name}", __DIR__)
  end
end
