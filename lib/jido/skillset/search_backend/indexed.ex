defmodule Jido.Skillset.SearchBackend.Indexed do
  @moduledoc """
  Indexed lexical search backend using snapshot postings and document stats.

  Ranking is BM25F-inspired with field-aware weighting over `id`, `title`, `tags`,
  and `body`. This backend only reads in-memory snapshot/ETS index structures and
  avoids markdown file parsing during query execution.
  """

  @behaviour Jido.Skillset.SearchBackend

  alias Jido.Skillset.SearchIndex
  alias Jido.Skillset.SearchIndex.Tokenizer
  alias Jido.Skillset.SearchIndex.Trigram
  alias Jido.Skillset.Snapshot

  @default_fields [:title, :tags, :body, :id]
  @valid_fields MapSet.new([:id, :title, :tags, :body])
  @default_limit 20
  @max_limit 200
  @default_operator :or
  @default_fuzzy false
  @default_fuzzy_max_expansions 3
  @max_fuzzy_max_expansions 10
  @default_fuzzy_min_similarity 0.2

  @k1 1.2
  @b 0.75

  @impl true
  def search(%Snapshot{} = snapshot, graph_id, query, opts)
      when is_binary(graph_id) and is_binary(query) do
    with :ok <- ensure_graph(snapshot, graph_id),
         {:ok, terms} <- normalize_terms(query, opts),
         {:ok, fields} <- normalize_fields(opts),
         {:ok, operator} <- normalize_operator(opts),
         {:ok, fuzzy?} <- normalize_fuzzy(opts) do
      limit = normalize_limit(opts)

      if terms == [] do
        {:ok, []}
      else
        corpus = normalize_corpus_stats(Snapshot.search_corpus_stats(snapshot))
        search_terms = expand_terms(snapshot, terms, fields, fuzzy?, opts)

        snapshot
        |> score_candidates(search_terms, fields, corpus)
        |> apply_operator(operator, length(terms))
        |> Enum.map(&to_result(snapshot, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&{-&1.score, &1.id})
        |> Enum.take(limit)
        |> then(&{:ok, &1})
      end
    end
  end

  def search(_snapshot, _graph_id, _query, _opts), do: {:error, :invalid_search_input}

  defp ensure_graph(%Snapshot{graph_id: graph_id}, graph_id), do: :ok
  defp ensure_graph(_snapshot, graph_id), do: {:error, {:unknown_graph, graph_id}}

  defp normalize_terms(query, opts) do
    tokenizer_opts =
      opts
      |> Keyword.get(:search_index_tokenizer_opts, [])
      |> Keyword.put(:dedupe, true)

    {:ok, Tokenizer.tokenize(query, tokenizer_opts)}
  end

  defp normalize_fields(opts) do
    case Keyword.get(opts, :fields, @default_fields) do
      fields when is_list(fields) ->
        fields
        |> Enum.map(&normalize_field/1)
        |> Enum.reduce_while({:ok, []}, fn
          {:ok, field}, {:ok, acc} -> {:cont, {:ok, [field | acc]}}
          {:error, reason}, _acc -> {:halt, {:error, reason}}
        end)
        |> case do
          {:ok, []} -> {:ok, @default_fields}
          {:ok, values} -> {:ok, Enum.reverse(values)}
          error -> error
        end

      field ->
        case normalize_field(field) do
          {:ok, value} -> {:ok, [value]}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp normalize_field(field) when field in [:id, :title, :tags, :body], do: {:ok, field}

  defp normalize_field(field) when is_binary(field) do
    case String.downcase(field) do
      "id" -> {:ok, :id}
      "title" -> {:ok, :title}
      "tags" -> {:ok, :tags}
      "body" -> {:ok, :body}
      _ -> {:error, {:invalid_search_field, field}}
    end
  end

  defp normalize_field(field), do: {:error, {:invalid_search_field, field}}

  defp normalize_operator(opts) do
    case Keyword.get(opts, :operator, @default_operator) do
      value when value in [:and, :or] ->
        {:ok, value}

      value when is_binary(value) ->
        case String.downcase(value) do
          "and" -> {:ok, :and}
          "or" -> {:ok, :or}
          _ -> {:error, {:invalid_search_operator, value}}
        end

      value ->
        {:error, {:invalid_search_operator, value}}
    end
  end

  defp normalize_limit(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      n when is_integer(n) and n > 0 and n <= @max_limit -> n
      n when is_integer(n) and n > @max_limit -> @max_limit
      _ -> @default_limit
    end
  end

  defp normalize_fuzzy(opts) do
    case Keyword.get(opts, :fuzzy, @default_fuzzy) do
      value when is_boolean(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case value |> String.trim() |> String.downcase() do
          "true" -> {:ok, true}
          "false" -> {:ok, false}
          _ -> {:error, {:invalid_search_fuzzy, value}}
        end

      value ->
        {:error, {:invalid_search_fuzzy, value}}
    end
  end

  defp normalize_fuzzy_max_expansions(opts) do
    case Keyword.get(opts, :fuzzy_max_expansions, @default_fuzzy_max_expansions) do
      n when is_integer(n) and n > 0 ->
        min(n, @max_fuzzy_max_expansions)

      _other ->
        @default_fuzzy_max_expansions
    end
  end

  defp normalize_fuzzy_min_similarity(opts) do
    case Keyword.get(opts, :fuzzy_min_similarity, @default_fuzzy_min_similarity) do
      n when is_integer(n) and n >= 0 and n <= 1 -> n / 1
      n when is_float(n) and n >= 0.0 and n <= 1.0 -> n
      _other -> @default_fuzzy_min_similarity
    end
  end

  defp normalize_corpus_stats(corpus) when is_map(corpus) do
    %{
      document_count: Map.get(corpus, :document_count, 0),
      avg_field_lengths:
        Map.get(corpus, :avg_field_lengths, SearchIndex.default_avg_field_lengths()),
      document_frequencies: Map.get(corpus, :document_frequencies, %{})
    }
  end

  defp expand_terms(_snapshot, terms, _fields, false, _opts) do
    Enum.map(terms, fn term ->
      %{query_term: term, index_term: term, boost: 1.0}
    end)
  end

  defp expand_terms(snapshot, terms, fields, true, opts) do
    max_expansions = normalize_fuzzy_max_expansions(opts)
    min_similarity = normalize_fuzzy_min_similarity(opts)

    Enum.flat_map(
      terms,
      &expand_term(snapshot, &1, fields, max_expansions, min_similarity)
    )
  end

  defp expand_term(snapshot, term, fields, max_expansions, min_similarity) do
    exact = %{query_term: term, index_term: term, boost: 1.0}

    if has_postings_for_term?(snapshot, term, fields) do
      [exact]
    else
      [exact | fuzzy_expansions(snapshot, term, max_expansions, min_similarity)]
    end
  end

  defp fuzzy_expansions(snapshot, term, max_expansions, min_similarity) do
    snapshot
    |> fuzzy_candidates(term, max_expansions, min_similarity)
    |> Enum.map(fn {candidate_term, similarity} ->
      %{query_term: term, index_term: candidate_term, boost: similarity}
    end)
  end

  defp has_postings_for_term?(snapshot, term, fields) do
    fields
    |> Enum.filter(&MapSet.member?(@valid_fields, &1))
    |> Enum.any?(fn field ->
      Snapshot.search_postings(snapshot, term, field) != []
    end)
  end

  defp fuzzy_candidates(snapshot, term, max_expansions, min_similarity) do
    term
    |> Trigram.term_trigrams()
    |> Enum.flat_map(&Snapshot.search_trigram_terms(snapshot, &1))
    |> Enum.reject(&(&1 == term))
    |> Enum.uniq()
    |> Enum.map(fn candidate_term ->
      {candidate_term, Trigram.jaccard_similarity(term, candidate_term)}
    end)
    |> Enum.filter(fn {_candidate_term, similarity} -> similarity >= min_similarity end)
    |> Enum.sort_by(fn {candidate_term, similarity} -> {-similarity, candidate_term} end)
    |> Enum.take(max_expansions)
  end

  defp score_candidates(snapshot, search_terms, fields, corpus) do
    search_terms
    |> Enum.reduce(%{}, &score_search_term(snapshot, &1, fields, corpus, &2))
    |> Map.values()
  end

  defp score_search_term(
         snapshot,
         %{query_term: _query_term, index_term: _index_term, boost: _boost} = search_term,
         fields,
         corpus,
         candidates
       ) do
    fields
    |> Enum.filter(&MapSet.member?(@valid_fields, &1))
    |> Enum.reduce(
      candidates,
      &score_index_term_field(snapshot, search_term, &1, corpus, &2)
    )
  end

  defp score_search_term(_snapshot, _search_term, _fields, _corpus, candidates), do: candidates

  defp score_index_term_field(
         snapshot,
         %{index_term: index_term} = search_term,
         field,
         corpus,
         candidates
       ) do
    Snapshot.search_postings(snapshot, index_term, field)
    |> Enum.reduce(candidates, fn {node_id, tf}, node_acc ->
      update_candidate(node_acc, snapshot, node_id, search_term, field, tf, corpus)
    end)
  end

  defp update_candidate(
         candidates,
         snapshot,
         node_id,
         %{query_term: query_term, index_term: index_term, boost: boost},
         field,
         tf,
         corpus
       ) do
    doc_stats = Snapshot.search_doc_stats(snapshot, node_id) || %{}

    increment =
      term_field_score(
        tf,
        corpus.document_count,
        Map.get(corpus.document_frequencies, index_term, 0),
        Map.get(doc_stats, field, 0),
        Map.get(corpus.avg_field_lengths, field, 0.0),
        field
      ) * max(boost, 0.0)

    Map.update(
      candidates,
      node_id,
      %{
        node_id: node_id,
        score: increment,
        matched_terms: MapSet.new([index_term]),
        matched_queries: MapSet.new([query_term]),
        matched_fields: MapSet.new([field])
      },
      fn candidate ->
        %{
          candidate
          | score: candidate.score + increment,
            matched_terms: MapSet.put(candidate.matched_terms, index_term),
            matched_queries: MapSet.put(candidate.matched_queries, query_term),
            matched_fields: MapSet.put(candidate.matched_fields, field)
        }
      end
    )
  end

  defp term_field_score(tf, doc_count, document_frequency, field_len, avg_field_len, field) do
    tf = normalize_non_negative_float(tf)
    doc_count = normalize_non_negative_float(doc_count)
    document_frequency = normalize_non_negative_float(document_frequency)
    field_len = normalize_non_negative_float(field_len)
    avg_field_len = normalize_non_negative_float(avg_field_len)

    idf = idf(doc_count, document_frequency)
    norm = normalization(field_len, avg_field_len)
    tf_component = tf * (@k1 + 1.0) / (tf + @k1 * norm)

    idf * tf_component * field_weight(field)
  end

  defp idf(doc_count, _document_frequency) when doc_count <= 0.0, do: 0.0

  defp idf(doc_count, document_frequency) do
    # BM25-style IDF with +1 smoothing.
    numerator = doc_count - document_frequency + 0.5
    denominator = document_frequency + 0.5
    :math.log(1.0 + max(numerator, 0.0) / max(denominator, 0.5))
  end

  defp normalization(_field_len, avg_field_len) when avg_field_len <= 0.0, do: 1.0

  defp normalization(field_len, avg_field_len) do
    1.0 - @b + @b * (field_len / avg_field_len)
  end

  defp normalize_non_negative_float(value) when is_integer(value) and value >= 0, do: value / 1
  defp normalize_non_negative_float(value) when is_float(value) and value >= 0.0, do: value
  defp normalize_non_negative_float(_value), do: 0.0

  defp field_weight(:title), do: 4.0
  defp field_weight(:tags), do: 3.0
  defp field_weight(:id), do: 2.0
  defp field_weight(:body), do: 1.0

  defp apply_operator(candidates, :and, term_count) do
    Enum.filter(candidates, fn candidate ->
      MapSet.size(candidate.matched_queries) == term_count
    end)
  end

  defp apply_operator(candidates, :or, term_count) do
    Enum.map(candidates, fn candidate ->
      coverage = MapSet.size(candidate.matched_queries) / max(term_count, 1)
      adjusted_score = candidate.score * (0.5 + 0.5 * coverage)
      %{candidate | score: adjusted_score}
    end)
  end

  defp to_result(snapshot, candidate) do
    case Snapshot.get_node(snapshot, candidate.node_id) do
      nil ->
        nil

      node ->
        %{
          id: node.id,
          title: node.title,
          path: node.path,
          tags: node.tags,
          score: score_to_int(candidate.score),
          matches: candidate.matched_fields |> MapSet.to_list() |> Enum.sort(),
          excerpt: excerpt(snapshot, candidate)
        }
    end
  end

  defp excerpt(snapshot, %{matched_fields: matched_fields, node_id: node_id, matched_terms: terms})
       when is_struct(matched_fields, MapSet) and is_struct(terms, MapSet) do
    if MapSet.member?(matched_fields, :body) do
      snapshot
      |> Snapshot.search_body_cache(node_id)
      |> excerpt_from_body(terms)
    else
      nil
    end
  end

  defp excerpt(_snapshot, _candidate), do: nil

  defp excerpt_from_body(body, matched_terms)
       when is_binary(body) and is_struct(matched_terms, MapSet) do
    downcased_body = String.downcase(body)

    term_match =
      matched_terms
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.flat_map(fn term ->
        case :binary.match(downcased_body, term) do
          {position, length} -> [{position, length}]
          :nomatch -> []
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> List.first()

    case term_match do
      {position, _length} ->
        start_at = max(position - 48, 0)
        snippet_length = min(byte_size(body) - start_at, 120)
        snippet = binary_part(body, start_at, snippet_length)

        snippet
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      nil ->
        nil
    end
  end

  defp excerpt_from_body(_body, _matched_terms), do: nil

  defp score_to_int(score) when is_float(score) do
    score
    |> max(0.0)
    |> Kernel.*(1000)
    |> round()
  end

  defp score_to_int(score) when is_integer(score) and score >= 0, do: score
  defp score_to_int(_score), do: 0
end
