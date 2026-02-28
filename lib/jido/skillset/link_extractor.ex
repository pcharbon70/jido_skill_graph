defmodule Jido.Skillset.LinkExtractor do
  @moduledoc """
  Extract link references from frontmatter and markdown bodies.
  """

  alias Jido.Skillset.{Edge, Node}

  @type link_ref :: %{
          required(:target) => String.t(),
          required(:rel) => Edge.relation(),
          optional(:label) => String.t() | nil,
          optional(:source) => :wiki | :frontmatter,
          optional(:source_span) => term()
        }

  @typed_keys ["related", "prereq", "extends", "contains", "references"]
  @typed_relations %{
    "related" => :related,
    "prereq" => :prereq,
    "extends" => :extends,
    "contains" => :contains,
    "references" => :references
  }
  @wiki_pattern ~r/\[\[([^\]]+)\]\]/

  @spec extract(binary(), keyword()) :: {:ok, [link_ref()]} | {:error, term()}
  def extract(markdown, opts \\ []) when is_binary(markdown) do
    frontmatter = Keyword.get(opts, :frontmatter, %{})

    with {:ok, fm_links} <- extract_frontmatter(frontmatter),
         {:ok, wiki_links} <- extract_wikilinks(markdown) do
      {:ok, fm_links ++ wiki_links}
    end
  end

  defp extract_frontmatter(frontmatter) when is_map(frontmatter) do
    links =
      frontmatter
      |> frontmatter_links_raw()
      |> Enum.flat_map(&expand_frontmatter_entry/1)

    normalize_links(links)
  end

  defp extract_frontmatter(_frontmatter), do: {:ok, []}

  defp extract_wikilinks(markdown) do
    markdown
    |> then(&Regex.scan(@wiki_pattern, &1, capture: :all_but_first))
    |> Enum.map(&List.first/1)
    |> Enum.map(&parse_wikilink_content/1)
    |> normalize_links()
  end

  defp frontmatter_links_raw(frontmatter) do
    direct_links =
      case Map.get(frontmatter, "links") do
        value when is_list(value) -> value
        _ -> []
      end

    typed_links =
      @typed_keys
      |> Enum.flat_map(fn key ->
        frontmatter
        |> Map.get(key)
        |> normalize_rel_value(key)
      end)

    direct_links ++ typed_links
  end

  defp normalize_rel_value(values, rel) when is_list(values) do
    Enum.map(values, fn value -> %{target: value, rel: rel} end)
  end

  defp normalize_rel_value(value, rel) when is_binary(value), do: [%{target: value, rel: rel}]
  defp normalize_rel_value(_value, _rel), do: []

  defp expand_frontmatter_entry(entry) when is_binary(entry),
    do: [%{target: entry, rel: :related, source: :frontmatter}]

  defp expand_frontmatter_entry(entry) when is_map(entry) do
    typed_map_entries =
      entry
      |> Enum.filter(fn {key, value} -> key in @typed_keys and not is_nil(value) end)
      |> Enum.flat_map(fn {key, value} ->
        value
        |> List.wrap()
        |> Enum.map(fn target -> %{target: target, rel: key, source: :frontmatter} end)
      end)

    case fetch_target(entry) do
      nil ->
        typed_map_entries

      target ->
        [
          Map.merge(
            %{target: target, rel: fetch_rel(entry), source: :frontmatter},
            fetch_optional(entry)
          )
          | typed_map_entries
        ]
    end
  end

  defp expand_frontmatter_entry(_entry), do: []

  defp fetch_target(entry) do
    entry["target"] || entry["to"] || entry["id"] || entry["ref"] || entry[:target] || entry[:to] ||
      entry[:id] || entry[:ref]
  end

  defp fetch_rel(entry) do
    rel = entry["rel"] || entry["relation"] || entry[:rel] || entry[:relation] || :related

    case Edge.normalize_relation(rel) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> :related
    end
  end

  defp fetch_optional(entry) do
    %{
      label: entry["label"] || entry[:label],
      source_span: entry["source_span"] || entry[:source_span]
    }
  end

  defp parse_wikilink_content(content) do
    {raw_target, label} = split_label(content)
    {rel, target} = split_relation(raw_target)

    %{target: target, rel: rel, label: label, source: :wiki}
  end

  defp split_label(content) do
    case String.split(content, "|", parts: 2) do
      [target, label] -> {String.trim(target), String.trim(label)}
      [target] -> {String.trim(target), nil}
    end
  end

  defp split_relation(content) do
    case String.split(content, ":", parts: 2) do
      [prefix, target] ->
        case Map.fetch(@typed_relations, prefix) do
          {:ok, relation} -> {relation, String.trim(target)}
          :error -> {:related, String.trim(content)}
        end

      _ ->
        {:related, String.trim(content)}
    end
  end

  defp normalize_links(links) do
    links
    |> Enum.reduce_while({:ok, []}, fn link, {:ok, acc} ->
      case normalize_link(link) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp normalize_link(%{target: raw_target, rel: rel} = link) when is_binary(raw_target) do
    with {:ok, normalized_rel} <- Edge.normalize_relation(rel) do
      target = normalize_target(raw_target)

      if target == "" do
        {:error, {:invalid_link_target, raw_target}}
      else
        {:ok,
         %{
           target: target,
           rel: normalized_rel,
           label: Map.get(link, :label),
           source: Map.get(link, :source),
           source_span: Map.get(link, :source_span)
         }}
      end
    end
  end

  defp normalize_link(_link), do: {:error, :invalid_link_entry}

  @spec normalize_target(String.t()) :: String.t()
  def normalize_target(raw_target) when is_binary(raw_target) do
    raw_target
    |> String.trim()
    |> strip_fragment()
    |> strip_file_extension()
    |> strip_skill_filename()
    |> Node.normalize_id()
  end

  defp strip_fragment(target) do
    target
    |> String.split(["#", "?"], parts: 2)
    |> List.first()
  end

  defp strip_file_extension(target) do
    if String.ends_with?(String.downcase(target), ".md") do
      String.slice(target, 0, byte_size(target) - 3)
    else
      target
    end
  end

  defp strip_skill_filename(target) do
    case String.downcase(Path.basename(target)) do
      "skill" -> Path.dirname(target)
      _ -> target
    end
  end
end
