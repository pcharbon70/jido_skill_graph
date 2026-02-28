defmodule JidoSkillGraph.SearchBackend.Indexed do
  @moduledoc """
  Indexed lexical search backend using snapshot postings and document stats.

  Ranking is BM25F-inspired with field-aware weighting over `id`, `title`, `tags`,
  and `body`. This backend only reads in-memory snapshot/ETS index structures and
  avoids markdown file parsing during query execution.
  """

  @behaviour JidoSkillGraph.SearchBackend

  alias JidoSkillGraph.{SearchIndex, Snapshot}
  alias JidoSkillGraph.SearchIndex.Tokenizer

  @default_fields [:title, :tags, :body, :id]
  @valid_fields MapSet.new([:id, :title, :tags, :body])
  @default_limit 20
  @max_limit 200
  @default_operator :or

  @k1 1.2
  @b 0.75

  @impl true
  def search(%Snapshot{} = snapshot, graph_id, query, opts)
      when is_binary(graph_id) and is_binary(query) do
    with :ok <- ensure_graph(snapshot, graph_id),
         {:ok, terms} <- normalize_terms(query, opts),
         {:ok, fields} <- normalize_fields(opts),
         {:ok, operator} <- normalize_operator(opts) do
      limit = normalize_limit(opts)

      if terms == [] do
        {:ok, []}
      else
        corpus = normalize_corpus_stats(Snapshot.search_corpus_stats(snapshot))

        snapshot
        |> score_candidates(terms, fields, corpus)
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

  defp normalize_corpus_stats(corpus) when is_map(corpus) do
    %{
      document_count: Map.get(corpus, :document_count, 0),
      avg_field_lengths:
        Map.get(corpus, :avg_field_lengths, SearchIndex.default_avg_field_lengths()),
      document_frequencies: Map.get(corpus, :document_frequencies, %{})
    }
  end

  defp score_candidates(snapshot, terms, fields, corpus) do
    terms
    |> Enum.reduce(%{}, &score_term(snapshot, &1, fields, corpus, &2))
    |> Map.values()
  end

  defp score_term(snapshot, term, fields, corpus, candidates) do
    fields
    |> Enum.filter(&MapSet.member?(@valid_fields, &1))
    |> Enum.reduce(candidates, &score_term_field(snapshot, term, &1, corpus, &2))
  end

  defp score_term_field(snapshot, term, field, corpus, candidates) do
    Snapshot.search_postings(snapshot, term, field)
    |> Enum.reduce(candidates, fn {node_id, tf}, node_acc ->
      update_candidate(node_acc, snapshot, node_id, term, field, tf, corpus)
    end)
  end

  defp update_candidate(candidates, snapshot, node_id, term, field, tf, corpus) do
    doc_stats = Snapshot.search_doc_stats(snapshot, node_id) || %{}

    increment =
      score_term_field(
        tf,
        corpus.document_count,
        Map.get(corpus.document_frequencies, term, 0),
        Map.get(doc_stats, field, 0),
        Map.get(corpus.avg_field_lengths, field, 0.0),
        field
      )

    Map.update(
      candidates,
      node_id,
      %{
        node_id: node_id,
        score: increment,
        matched_terms: MapSet.new([term]),
        matched_fields: MapSet.new([field])
      },
      fn candidate ->
        %{
          candidate
          | score: candidate.score + increment,
            matched_terms: MapSet.put(candidate.matched_terms, term),
            matched_fields: MapSet.put(candidate.matched_fields, field)
        }
      end
    )
  end

  defp score_term_field(tf, doc_count, document_frequency, field_len, avg_field_len, field) do
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
      MapSet.size(candidate.matched_terms) == term_count
    end)
  end

  defp apply_operator(candidates, :or, term_count) do
    Enum.map(candidates, fn candidate ->
      coverage = MapSet.size(candidate.matched_terms) / max(term_count, 1)
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
          excerpt: nil
        }
    end
  end

  defp score_to_int(score) when is_float(score) do
    score
    |> max(0.0)
    |> Kernel.*(1000)
    |> round()
  end

  defp score_to_int(score) when is_integer(score) and score >= 0, do: score
  defp score_to_int(_score), do: 0
end
