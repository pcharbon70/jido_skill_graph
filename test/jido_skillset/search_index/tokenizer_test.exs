defmodule Jido.Skillset.SearchIndex.TokenizerTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.SearchIndex.Tokenizer

  test "tokenize/2 normalizes case and punctuation" do
    assert Tokenizer.tokenize("Alpha, beta! GAmma?") == ["alpha", "beta", "gamma"]
  end

  test "tokenize/2 applies stopwords and length bounds" do
    assert Tokenizer.tokenize("an alpha the beta skill", stopwords: ["the"], min_token_length: 3) ==
             ["alpha", "beta", "skill"]
  end

  test "tokenize/2 supports dedupe mode" do
    assert Tokenizer.tokenize("alpha alpha beta", dedupe: true) == ["alpha", "beta"]
  end

  test "token_frequencies/2 counts repeated terms" do
    assert Tokenizer.token_frequencies("alpha beta alpha") == %{"alpha" => 2, "beta" => 1}
  end
end
