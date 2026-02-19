defmodule JidoSkillGraph.SearchBackend.Basic do
  @moduledoc """
  Baseline substring search over node id/title/tags/body.
  """

  @behaviour JidoSkillGraph.SearchBackend

  alias JidoSkillGraph.{Node, SkillFile, Snapshot}

  @default_fields [:title, :tags, :body, :id]
  @default_limit 20
  @max_limit 200
  @valid_fields MapSet.new([:id, :title, :tags, :body])

  @impl true
  def search(%Snapshot{} = snapshot, graph_id, query, opts)
      when is_binary(graph_id) and is_binary(query) do
    with :ok <- ensure_graph(snapshot, graph_id),
         {:ok, terms} <- normalize_terms(query),
         {:ok, fields} <- normalize_fields(opts) do
      limit = normalize_limit(opts)

      if terms == [] do
        {:ok, []}
      else
        snapshot.nodes
        |> Map.values()
        |> Enum.map(&rank_node(&1, terms, fields))
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

  defp normalize_terms(query) do
    terms =
      query
      |> String.trim()
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.uniq()

    {:ok, terms}
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
          {:ok, fields} -> {:ok, Enum.reverse(fields)}
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

  defp normalize_limit(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      n when is_integer(n) and n > 0 and n <= @max_limit -> n
      n when is_integer(n) and n > @max_limit -> @max_limit
      _ -> @default_limit
    end
  end

  defp rank_node(%Node{} = node, terms, fields) do
    body = if :body in fields, do: read_body(node), else: ""

    field_values = %{
      id: String.downcase(node.id),
      title: String.downcase(node.title || ""),
      tags: node.tags |> Enum.join(" ") |> String.downcase(),
      body: String.downcase(body)
    }

    {score, matches} =
      fields
      |> Enum.filter(&MapSet.member?(@valid_fields, &1))
      |> Enum.reduce({0, []}, fn field, {score, matches} ->
        text = Map.fetch!(field_values, field)
        hits = Enum.count(terms, &String.contains?(text, &1))

        if hits > 0 do
          {score + hits * field_weight(field), [field | matches]}
        else
          {score, matches}
        end
      end)

    if score > 0 do
      %{
        id: node.id,
        title: node.title,
        path: node.path,
        tags: node.tags,
        score: score,
        matches: matches |> Enum.uniq() |> Enum.sort(),
        excerpt: excerpt(body, terms)
      }
    end
  end

  defp read_body(%Node{placeholder?: true}), do: ""

  defp read_body(%Node{body_ref: path}) when is_binary(path) do
    case SkillFile.parse(path) do
      {:ok, document} -> document.body
      {:error, _reason} -> ""
    end
  end

  defp read_body(_node), do: ""

  defp excerpt("", _terms), do: nil

  defp excerpt(body, terms) do
    downcased = String.downcase(body)

    case Enum.find(terms, &String.contains?(downcased, &1)) do
      nil ->
        nil

      term ->
        index = :binary.match(downcased, term)

        case index do
          {position, _length} ->
            start_at = max(position - 48, 0)
            length = min(byte_size(body) - start_at, 120)
            snippet = binary_part(body, start_at, length)

            snippet
            |> String.replace(~r/\s+/, " ")
            |> String.trim()

          :nomatch ->
            nil
        end
    end
  end

  defp field_weight(:title), do: 4
  defp field_weight(:tags), do: 3
  defp field_weight(:id), do: 2
  defp field_weight(:body), do: 1
end
