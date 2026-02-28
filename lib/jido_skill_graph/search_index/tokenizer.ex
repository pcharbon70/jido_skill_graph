defmodule JidoSkillGraph.SearchIndex.Tokenizer do
  @moduledoc """
  Normalization and tokenization helpers for indexed search.

  This module defines deterministic tokenization rules used to compute index
  metadata in early rollout phases.
  """

  @default_min_token_length 2
  @default_max_token_length 64

  @type option ::
          {:min_token_length, pos_integer()}
          | {:max_token_length, pos_integer()}
          | {:stopwords, [String.t()] | MapSet.t()}
          | {:dedupe, boolean()}

  @spec tokenize(String.t(), [option()]) :: [String.t()]
  def tokenize(text, opts \\ [])

  def tokenize(text, opts) when is_binary(text) and is_list(opts) do
    min_length =
      normalize_min_length(Keyword.get(opts, :min_token_length, @default_min_token_length))

    max_length =
      normalize_max_length(Keyword.get(opts, :max_token_length, @default_max_token_length))

    stopwords = normalize_stopwords(Keyword.get(opts, :stopwords, []))
    dedupe? = Keyword.get(opts, :dedupe, false)

    text
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]]+/u, trim: true)
    |> Enum.map(&normalize_token/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(fn token ->
      String.length(token) >= min_length and
        String.length(token) <= max_length and
        not MapSet.member?(stopwords, token)
    end)
    |> maybe_dedupe(dedupe?)
  end

  def tokenize(_text, _opts), do: []

  @spec token_frequencies(String.t(), [option()]) :: %{optional(String.t()) => non_neg_integer()}
  def token_frequencies(text, opts \\ [])

  def token_frequencies(text, opts) when is_binary(text) and is_list(opts) do
    text
    |> tokenize(opts)
    |> Enum.reduce(%{}, fn token, acc -> Map.update(acc, token, 1, &(&1 + 1)) end)
  end

  def token_frequencies(_text, _opts), do: %{}

  @spec normalize_token(String.t()) :: String.t()
  def normalize_token(token) when is_binary(token) do
    token
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^[:alnum:]]+/u, "")
  end

  def normalize_token(_token), do: ""

  defp normalize_min_length(value) when is_integer(value) and value >= 1, do: value
  defp normalize_min_length(_value), do: @default_min_token_length

  defp normalize_max_length(value) when is_integer(value) and value >= 1, do: value
  defp normalize_max_length(_value), do: @default_max_token_length

  defp normalize_stopwords(%MapSet{} = stopwords), do: stopwords

  defp normalize_stopwords(stopwords) when is_list(stopwords) do
    stopwords
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end

  defp normalize_stopwords(_stopwords), do: MapSet.new()

  defp maybe_dedupe(tokens, true), do: Enum.uniq(tokens)
  defp maybe_dedupe(tokens, _dedupe?), do: tokens
end
