defmodule JidoSkillGraph.Builder do
  @moduledoc """
  Build pipeline entrypoint: discover -> parse -> extract -> resolve -> snapshot.
  """

  alias JidoSkillGraph.{Discovery, Edge, LinkExtractor, Node, SkillFile, Snapshot, Topology}

  @type snapshot :: Snapshot.t()

  @type build_option ::
          {:root, Path.t()}
          | {:graph_id, String.t()}
          | {:manifest_path, Path.t()}
          | {:unresolved_link_policy, Snapshot.unresolved_link_policy()}
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
         {:ok, nodes, link_specs} <- parse_nodes(discovery.files, discovery.root, graph_id),
         {:ok, edges, warnings} <- resolve_links(nodes, link_specs),
         do: build_snapshot(opts, discovery, graph_id, nodes, edges, warnings, link_specs)
  end

  defp build_snapshot(opts, discovery, graph_id, nodes, edges, warnings, link_specs) do
    with {:ok, snapshot} <-
           Snapshot.new(
             graph: nil,
             graph_id: graph_id,
             manifest: discovery.manifest,
             version: Keyword.get(opts, :version, 0),
             nodes: nodes,
             edges: edges,
             unresolved_link_policy: Keyword.get(opts, :unresolved_link_policy, :warn_and_skip),
             warnings: warnings,
             stats: %{
               mode: :pure,
               files: length(discovery.files),
               parsed_nodes: length(nodes),
               extracted_links: length(link_specs),
               parsed_edges: length(edges)
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
      warnings: snapshot.warnings
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

  defp parse_nodes(files, root, graph_id) do
    files
    |> Enum.reduce_while({:ok, [], []}, fn path, {:ok, nodes, link_specs} ->
      case parse_node(path, root, graph_id) do
        {:ok, node, links} ->
          {:cont, {:ok, [node | nodes], links ++ link_specs}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, nodes, link_specs} -> {:ok, Enum.reverse(nodes), Enum.reverse(link_specs)}
      error -> error
    end
  end

  defp parse_node(path, root, graph_id) do
    with {:ok, %SkillFile{} = document} <- SkillFile.parse(path),
         {:ok, node} <- build_node(document, root, graph_id),
         {:ok, links} <- LinkExtractor.extract(document.body, frontmatter: document.frontmatter) do
      {:ok, node, annotate_links(node.id, path, links)}
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
