defmodule JidoSkillGraph.LinkExtractor do
  @moduledoc """
  Extract link references from frontmatter and markdown bodies.

  Link semantics are implemented in later phases.
  """

  @spec extract(binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def extract(markdown, _opts \\ []) when is_binary(markdown) do
    {:ok, []}
  end
end
