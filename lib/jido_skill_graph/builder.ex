defmodule JidoSkillGraph.Builder do
  @moduledoc """
  Build pipeline entrypoint: discover -> parse -> extract -> resolve -> snapshot.
  """

  alias JidoSkillGraph.{
    Discovery,
    Edge,
    LinkExtractor,
    Node,
    SearchIndex,
    SkillFile,
    Snapshot,
    Topology
  }

  alias JidoSkillGraph.SearchIndex.Tokenizer

  @type snapshot :: Snapshot.t()

  @type build_option ::
          {:root, Path.t()}
          | {:graph_id, String.t()}
          | {:manifest_path, Path.t()}
          | {:unresolved_link_policy, Snapshot.unresolved_link_policy()}
          | {:search_index_build_version, pos_integer()}
          | {:search_index_tokenizer_opts, [Tokenizer.option()]}
          | {:version, non_neg_integer()}

  @type link_spec :: %{
          from: String.t(),
          to: String.t(),
          rel: Edge.relation(),
          label: String.t() | nil,
          source: :wiki | :frontmatter,
          source_span: term(),
          source_path: Path.t()
        }

  @spec build([build_option()]) :: {:ok, snapshot()} | {:error, term()}
  def build(opts \\ []) do
    with {:ok, discovery} <- discover(opts),
         {:ok, graph_id} <- resolve_graph_id(opts, discovery),
         {:ok, nodes, link_specs, field_lengths, postings, document_frequencies} <-
           parse_nodes(
             discovery.files,
             discovery.root,
             graph_id,
             Keyword.get(opts, :search_index_tokenizer_opts, [])
           ),
         {:ok, edges, warnings} <- resolve_links(nodes, link_specs),
         do:
           build_snapshot(%{
             opts: opts,
             discovery: discovery,
             graph_id: graph_id,
             nodes: nodes,
             edges: edges,
             warnings: warnings,
             link_specs: link_specs,
             field_lengths: field_lengths,
             postings: postings,
             document_frequencies: document_frequencies
           })
  end

  defp build_snapshot(%{
         opts: opts,
         discovery: discovery,
         graph_id: graph_id,
         nodes: nodes,
         edges: edges,
         warnings: warnings,
         link_specs: link_specs,
         field_lengths: field_lengths,
         postings: postings,
         document_frequencies: document_frequencies
       }) do
    with {:ok, search_index} <-
           build_search_index(field_lengths, postings, document_frequencies, opts),
         {:ok, snapshot} <-
           Snapshot.new(
             graph: nil,
             graph_id: graph_id,
             manifest: discovery.manifest,
             version: Keyword.get(opts, :version, 0),
             nodes: nodes,
             edges: edges,
             unresolved_link_policy: Keyword.get(opts, :unresolved_link_policy, :warn_and_skip),
             search_index: search_index,
             warnings: warnings,
             stats: %{
               mode: :pure,
               files: length(discovery.files),
               parsed_nodes: length(nodes),
               extracted_links: length(link_specs),
               parsed_edges: length(edges),
               index_documents: map_size(field_lengths)
             }
           ) do
      graph = Topology.build(snapshot.nodes, snapshot.edges)

      stats =
        snapshot.stats
        |> Map.merge(%{
          graph_vertices: Graph.num_vertices(graph),
          graph_edges: Graph.num_edges(graph),
          snapshot_checksum: snapshot_checksum(snapshot)
        })

      {:ok, %{snapshot | graph: graph, stats: stats}}
    end
  end

  defp snapshot_checksum(%Snapshot{} = snapshot) do
    payload = %{
      graph_id: snapshot.graph_id,
      version: snapshot.version,
      nodes: snapshot_digest_nodes(snapshot.nodes),
      edges: snapshot_digest_edges(snapshot.edges),
      warnings: snapshot.warnings,
      search_index: snapshot_digest_search_index(snapshot.search_index)
    }

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(payload))
    |> Base.encode16(case: :lower)
  end

  defp snapshot_digest_nodes(nodes) do
    nodes
    |> Map.values()
    |> Enum.map(fn node ->
      {node.id, node.path, node.title, node.checksum, node.tags, node.placeholder?}
    end)
    |> Enum.sort()
  end

  defp snapshot_digest_edges(edges) do
    edges
    |> Enum.map(fn edge -> {edge.from, edge.to, edge.rel, edge.label, edge.source_span} end)
    |> Enum.sort()
  end

  defp snapshot_digest_search_index(nil), do: nil

  defp snapshot_digest_search_index(%SearchIndex{} = search_index) do
    %{
      build_version: search_index.build_version,
      document_count: search_index.document_count,
      avg_field_lengths: search_index.avg_field_lengths,
      body_cache_meta: search_index.body_cache_meta,
      meta: search_index.meta
    }
  end

  defp discover(opts) do
    Discovery.discover(
      root: Keyword.get(opts, :root, "."),
      manifest_path: Keyword.get(opts, :manifest_path)
    )
  end

  defp resolve_graph_id(opts, discovery) do
    manifest_graph_id =
      case discovery.manifest do
        nil -> nil
        manifest -> manifest.graph_id
      end

    graph_id =
      Keyword.get(opts, :graph_id) || manifest_graph_id || default_graph_id(discovery.root)

    if is_binary(graph_id) and graph_id != "" do
      {:ok, graph_id}
    else
      {:error, :invalid_graph_id}
    end
  end

  defp default_graph_id(root) do
    root
    |> Path.basename()
    |> Node.normalize_id()
  end

  defp parse_nodes(files, root, graph_id, tokenizer_opts) do
    files
    |> Enum.reduce_while(
      {:ok, [], [], %{}, %{}, %{}},
      fn path, {:ok, nodes, link_specs, field_lengths, postings, document_frequencies} ->
        case parse_node(path, root, graph_id, tokenizer_opts) do
          {:ok, node, links, node_field_lengths, node_postings, node_terms} ->
            {:cont,
             {:ok, [node | nodes], links ++ link_specs,
              Map.put(field_lengths, node.id, node_field_lengths),
              merge_postings(postings, node.id, node_postings),
              merge_document_frequencies(document_frequencies, node_terms)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, nodes, link_specs, field_lengths, postings, document_frequencies} ->
        {:ok, Enum.reverse(nodes), Enum.reverse(link_specs), field_lengths, postings,
         document_frequencies}

      error ->
        error
    end
  end

  defp parse_node(path, root, graph_id, tokenizer_opts) do
    with {:ok, %SkillFile{} = document} <- SkillFile.parse(path),
         {:ok, node} <- build_node(document, root, graph_id),
         {:ok, links} <- LinkExtractor.extract(document.body, frontmatter: document.frontmatter) do
      {node_field_lengths, node_postings, node_terms} =
        node_search_index_data(node, document, tokenizer_opts)

      {:ok, node, annotate_links(node.id, path, links), node_field_lengths, node_postings,
       node_terms}
    end
  end

  defp build_node(%SkillFile{} = document, root, graph_id) do
    frontmatter = document.frontmatter

    Node.new(
      graph_id: graph_id,
      path: document.path,
      root: root,
      slug: frontmatter["slug"] || frontmatter["id"],
      title: frontmatter["title"],
      tags: normalize_tags(frontmatter["tags"]),
      checksum: document.checksum,
      body_ref: document.path,
      meta: %{frontmatter: frontmatter}
    )
  end

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(_tags), do: []

  defp node_search_index_data(node, document, tokenizer_opts) do
    token_frequencies = %{
      id: Tokenizer.token_frequencies(node.id, tokenizer_opts),
      title: Tokenizer.token_frequencies(node.title || "", tokenizer_opts),
      tags: Tokenizer.token_frequencies(Enum.join(node.tags, " "), tokenizer_opts),
      body: Tokenizer.token_frequencies(document.body, tokenizer_opts)
    }

    field_lengths =
      token_frequencies
      |> Enum.into(%{}, fn {field, frequencies} ->
        {field, Enum.reduce(frequencies, 0, fn {_term, tf}, acc -> acc + tf end)}
      end)

    postings =
      token_frequencies
      |> Enum.reduce(%{}, fn {field, frequencies}, acc ->
        Enum.reduce(frequencies, acc, fn {term, tf}, inner_acc ->
          Map.put(inner_acc, {term, field}, tf)
        end)
      end)

    unique_terms =
      token_frequencies
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()

    {field_lengths, postings, unique_terms}
  end

  defp merge_postings(acc, node_id, node_postings) do
    Enum.reduce(node_postings, acc, fn {{term, field}, tf}, posting_acc ->
      Map.update(posting_acc, {term, field}, [{node_id, tf}], fn rows ->
        [{node_id, tf} | rows]
      end)
    end)
  end

  defp merge_document_frequencies(acc, unique_terms) do
    Enum.reduce(unique_terms, acc, fn term, frequencies_acc ->
      Map.update(frequencies_acc, term, 1, &(&1 + 1))
    end)
  end

  defp build_search_index(field_lengths, postings, document_frequencies, opts) do
    postings =
      postings
      |> Enum.into(%{}, fn {key, rows} ->
        {key, Enum.sort_by(rows, &elem(&1, 0))}
      end)

    SearchIndex.from_field_lengths(
      field_lengths,
      build_version: Keyword.get(opts, :search_index_build_version, 1),
      meta: %{
        tokenizer: Keyword.get(opts, :search_index_tokenizer_opts, []),
        field_lengths_by_doc: field_lengths,
        postings: postings,
        document_frequencies: document_frequencies
      }
    )
  end

  defp annotate_links(node_id, source_path, links) do
    Enum.map(links, fn link ->
      %{
        from: node_id,
        to: link.target,
        rel: link.rel,
        label: link.label,
        source: link.source,
        source_span: link.source_span,
        source_path: source_path
      }
    end)
  end

  defp resolve_links(nodes, link_specs) do
    node_by_id = Map.new(nodes, &{&1.id, &1})
    basename_index = build_basename_index(nodes)

    link_specs
    |> Enum.reduce_while({:ok, [], []}, fn link, {:ok, edges, warnings} ->
      case resolve_link(link, node_by_id, basename_index) do
        {:ok, edge} -> {:cont, {:ok, [edge | edges], warnings}}
        {:skip, warning} -> {:cont, {:ok, edges, [warning | warnings]}}
        {:error, reason} -> {:halt, {:error, {:invalid_edge, link, reason}}}
      end
    end)
    |> case do
      {:ok, edges, warnings} -> {:ok, Enum.reverse(edges), Enum.reverse(warnings)}
      error -> error
    end
  end

  defp resolve_link(link, node_by_id, basename_index) do
    case resolve_link_target(link, node_by_id, basename_index) do
      {:ok, target_id} -> build_edge(link, target_id)
      {:unresolved, unresolved_id} -> build_edge(link, unresolved_id)
      {:skip, warning} -> {:skip, warning}
    end
  end

  defp build_edge(link, target_id) do
    Edge.new(
      from: link.from,
      to: target_id,
      rel: link.rel,
      label: link.label,
      source_span: link.source_span
    )
  end

  defp build_basename_index(nodes) do
    Enum.reduce(nodes, %{}, fn %Node{id: id}, acc ->
      basename = id |> String.split("/") |> List.last()
      Map.update(acc, basename, [id], &[id | &1])
    end)
  end

  defp resolve_link_target(link, node_by_id, basename_index) do
    target = link.to

    cond do
      Map.has_key?(node_by_id, target) ->
        {:ok, target}

      String.contains?(target, "/") ->
        resolve_by_suffix(target, node_by_id)

      true ->
        resolve_by_basename(target, basename_index)
    end
  end

  defp resolve_by_suffix(target, node_by_id) do
    matches =
      node_by_id
      |> Map.keys()
      |> Enum.filter(&String.ends_with?(&1, "/#{target}"))

    case matches do
      [match] -> {:ok, match}
      [] -> {:unresolved, target}
      many -> {:skip, "ambiguous target '#{target}' matched #{Enum.join(Enum.sort(many), ", ")}"}
    end
  end

  defp resolve_by_basename(target, basename_index) do
    case Map.get(basename_index, target, []) do
      [match] -> {:ok, match}
      [] -> {:unresolved, target}
      many -> {:skip, "ambiguous target '#{target}' matched #{Enum.join(Enum.sort(many), ", ")}"}
    end
  end
end
