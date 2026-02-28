defmodule JidoSkillGraph.SearchIndex.Trigram do
  @moduledoc """
  Trigram helpers for typo-tolerant term expansion.
  """

  alias JidoSkillGraph.SearchIndex.Tokenizer

  @type term_trigram :: String.t()

  @spec term_trigrams(String.t()) :: [term_trigram()]
  def term_trigrams(term) when is_binary(term) do
    normalized = Tokenizer.normalize_token(term)

    case String.graphemes(normalized) do
      [] -> []
      [_a] -> [normalized]
      [_a, _b] -> [normalized]
      graphemes -> grapheme_trigrams(graphemes)
    end
  end

  def term_trigrams(_term), do: []

  @spec dictionary_entries(String.t()) :: [{term_trigram(), String.t()}]
  def dictionary_entries(term) when is_binary(term) do
    normalized = Tokenizer.normalize_token(term)

    if normalized == "" do
      []
    else
      term_trigrams(normalized)
      |> Enum.map(fn trigram -> {trigram, normalized} end)
    end
  end

  def dictionary_entries(_term), do: []

  @spec jaccard_similarity(String.t(), String.t()) :: float()
  def jaccard_similarity(left, right) when is_binary(left) and is_binary(right) do
    left_set = left |> term_trigrams() |> MapSet.new()
    right_set = right |> term_trigrams() |> MapSet.new()

    union_size =
      left_set
      |> MapSet.union(right_set)
      |> MapSet.size()

    if union_size == 0 do
      0.0
    else
      intersection_size =
        left_set
        |> MapSet.intersection(right_set)
        |> MapSet.size()

      intersection_size / union_size
    end
  end

  def jaccard_similarity(_left, _right), do: 0.0

  defp grapheme_trigrams(graphemes) do
    last_start = length(graphemes) - 3

    0..last_start
    |> Enum.map(fn start ->
      graphemes
      |> Enum.slice(start, 3)
      |> Enum.join()
    end)
    |> Enum.uniq()
  end
end
