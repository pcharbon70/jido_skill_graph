defmodule Jido.Skillset.ManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.Manifest

  test "load/1 parses manifest fields" do
    manifest_path = fixture_path("manifest_subset/graph.yml")

    assert {:ok, manifest} = Manifest.load(manifest_path)

    assert manifest.graph_id == "manifest-subset"
    assert manifest.includes == ["selected/**"]
    assert manifest.root == nil
  end

  defp fixture_path(name) do
    Path.expand("../fixtures/phase4/#{name}", __DIR__)
  end
end
