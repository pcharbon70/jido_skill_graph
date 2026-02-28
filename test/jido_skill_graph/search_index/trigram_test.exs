defmodule JidoSkillGraph.SearchIndex.TrigramTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.SearchIndex.Trigram

  test "term_trigrams/1 generates unique trigrams for long terms" do
    assert Trigram.term_trigrams("alpha") == ["alp", "lph", "pha"]
  end

  test "term_trigrams/1 returns normalized token for short terms" do
    assert Trigram.term_trigrams("AI") == ["ai"]
    assert Trigram.term_trigrams(" a! ") == ["a"]
  end

  test "dictionary_entries/1 returns trigram-term rows" do
    assert Trigram.dictionary_entries("alpha") == [
             {"alp", "alpha"},
             {"lph", "alpha"},
             {"pha", "alpha"}
           ]
  end

  test "jaccard_similarity/2 computes overlap between misspelled terms" do
    score = Trigram.jaccard_similarity("alpah", "alpha")

    assert is_float(score)
    assert_in_delta(score, 0.2, 0.0001)
  end
end
