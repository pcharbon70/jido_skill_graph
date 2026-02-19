defmodule JidoSkillGraph.BuilderTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.Builder

  test "build/1 discovers skill files and extracts frontmatter + wiki links" do
    root = fixture_path("basic")

    assert {:ok, snapshot} = Builder.build(root: root, graph_id: "basic")

    assert snapshot.nodes |> Map.keys() |> Enum.sort() == ["alpha", "beta"]

    assert Enum.any?(snapshot.edges, fn edge ->
             edge.from == "alpha" and edge.to == "beta" and edge.rel == :prereq
           end)

    assert Enum.any?(snapshot.edges, fn edge ->
             edge.from == "alpha" and edge.to == "beta" and edge.rel == :related
           end)

    assert Enum.any?(snapshot.warnings, &String.contains?(&1, "unresolved edge alpha -> gamma"))
  end

  test "build/1 supports cyclic graphs" do
    root = fixture_path("cycle")

    assert {:ok, snapshot} = Builder.build(root: root, graph_id: "cycle")

    assert Enum.any?(snapshot.edges, &(&1.from == "a" and &1.to == "b"))
    assert Enum.any?(snapshot.edges, &(&1.from == "b" and &1.to == "a"))
  end

  test "build/1 warns and skips ambiguous targets" do
    root = fixture_path("ambiguous")

    assert {:ok, snapshot} = Builder.build(root: root, graph_id: "ambiguous")

    assert snapshot.edges == []
    assert Enum.any?(snapshot.warnings, &String.contains?(&1, "ambiguous target 'intro'"))
  end

  test "build/1 respects manifest includes" do
    root = fixture_path("manifest_subset")

    assert {:ok, snapshot} = Builder.build(root: root)

    assert snapshot.graph_id == "manifest-subset"
    assert snapshot.nodes |> Map.keys() |> Enum.sort() == ["selected/a"]
  end

  test "build/1 returns parse errors for malformed frontmatter" do
    root = fixture_path("malformed_frontmatter")

    assert {:error, {:invalid_frontmatter, path, _reason}} =
             Builder.build(root: root, graph_id: "bad")

    assert String.ends_with?(path, "/bad/SKILL.md")
  end

  defp fixture_path(name) do
    Path.expand("../fixtures/phase4/#{name}", __DIR__)
  end
end
