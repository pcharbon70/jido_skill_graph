defmodule Jido.Skillset.LinkExtractorTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.LinkExtractor

  test "extract/2 parses typed wiki links" do
    markdown = "Use [[prereq:alpha]] and [[extends:beta|Beta Doc]] and [[gamma]]."

    assert {:ok, links} = LinkExtractor.extract(markdown)

    assert Enum.any?(links, &(&1.target == "alpha" and &1.rel == :prereq))

    assert Enum.any?(
             links,
             &(&1.target == "beta" and &1.rel == :extends and &1.label == "Beta Doc")
           )

    assert Enum.any?(links, &(&1.target == "gamma" and &1.rel == :related))
  end

  test "extract/2 parses frontmatter links and typed keys" do
    frontmatter = %{
      "links" => [%{"target" => "intro", "rel" => "references"}],
      "prereq" => ["foundation"]
    }

    assert {:ok, links} = LinkExtractor.extract("", frontmatter: frontmatter)

    assert Enum.any?(links, &(&1.target == "intro" and &1.rel == :references))
    assert Enum.any?(links, &(&1.target == "foundation" and &1.rel == :prereq))
  end

  test "normalize_target/1 canonicalizes path-like targets and markdown extension" do
    assert LinkExtractor.normalize_target("Knowledge-Work/Graph-Structure/SKILL.md") ==
             "knowledge-work/graph-structure"
  end
end
