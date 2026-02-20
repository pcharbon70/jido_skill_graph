defmodule JidoSkillGraphMCP.Tools do
  @moduledoc """
  MCP tool schema and dispatch handlers for skill graph operations.
  """

  alias JidoSkillGraph.Edge

  @spec definitions() :: [map()]
  def definitions do
    [
      %{
        "name" => "skills_graph.list",
        "description" => "List available skill graphs currently loaded.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{},
          "additionalProperties" => false
        }
      },
      %{
        "name" => "skills_graph.topology",
        "description" => "Return graph topology and optional node/edge details.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "graph_id" => %{"type" => "string"},
            "include_nodes" => %{"type" => "boolean"},
            "include_edges" => %{"type" => "boolean"}
          },
          "required" => ["graph_id"],
          "additionalProperties" => false
        }
      },
      %{
        "name" => "skills_graph.node_links",
        "description" =>
          "Return in/out links for a node, with optional neighbor traversal and relation filtering.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "graph_id" => %{"type" => "string"},
            "node_id" => %{"type" => "string"},
            "direction" => %{"type" => "string", "enum" => ["out", "in", "both"]},
            "rel" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "array"}]},
            "hops" => %{"type" => "integer"},
            "include_neighbors" => %{"type" => "boolean"}
          },
          "required" => ["graph_id", "node_id"],
          "additionalProperties" => false
        }
      },
      %{
        "name" => "skills_graph.search",
        "description" => "Search graph nodes using the configured search backend.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "graph_id" => %{"type" => "string"},
            "query" => %{"type" => "string"},
            "limit" => %{"type" => "integer"},
            "fields" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "required" => ["graph_id", "query"],
          "additionalProperties" => false
        }
      }
    ]
  end

  @spec call(String.t(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  def call(name, params \\ %{}, opts \\ []) when is_binary(name) and is_map(params) do
    store = Keyword.get(opts, :store, JidoSkillGraph.Store)

    case name do
      "skills_graph.list" ->
        list(store)

      "skills_graph.topology" ->
        topology(params, store)

      "skills_graph.node_links" ->
        node_links(params, store)

      "skills_graph.search" ->
        search(params, store)

      _ ->
        error(:unknown_tool, "Unknown tool '#{name}'")
    end
  end

  defp list(store) do
    graphs = JidoSkillGraph.list_graphs(store: store)
    {:ok, %{"graphs" => graphs, "count" => length(graphs)}}
  end

  defp topology(params, store) do
    with {:ok, graph_id} <- required_string(params, "graph_id"),
         {:ok, topology} <-
           JidoSkillGraph.topology(graph_id,
             store: store,
             include_nodes: boolean_param(params, "include_nodes", false),
             include_edges: boolean_param(params, "include_edges", false)
           ) do
      {:ok, stringify(topology)}
    else
      {:error, reason} -> error(reason, "Failed to load graph topology")
    end
  end

  defp node_links(params, store) do
    with {:ok, graph_id} <- required_string(params, "graph_id"),
         {:ok, node_id} <- required_string(params, "node_id"),
         {:ok, direction} <- direction_param(params),
         {:ok, out_links, in_links} <- fetch_links(graph_id, node_id, direction, params, store) do
      payload =
        %{
          "graph_id" => graph_id,
          "node_id" => node_id,
          "direction" => Atom.to_string(direction),
          "out_links" => Enum.map(out_links, &edge_to_map/1),
          "in_links" => Enum.map(in_links, &edge_to_map/1)
        }
        |> maybe_add_neighbors(graph_id, node_id, direction, params, store)

      {:ok, payload}
    else
      {:error, reason} -> error(reason, "Failed to resolve node links")
    end
  end

  defp search(params, store) do
    with {:ok, graph_id} <- required_string(params, "graph_id"),
         {:ok, query} <- required_string(params, "query"),
         {:ok, results} <-
           JidoSkillGraph.search(graph_id, query,
             store: store,
             limit: integer_param(params, "limit", nil),
             fields: list_param(params, "fields", nil)
           ) do
      {:ok, %{"graph_id" => graph_id, "query" => query, "results" => stringify(results)}}
    else
      {:error, reason} -> error(reason, "Failed to execute search")
    end
  end

  defp fetch_links(graph_id, node_id, :out, params, store) do
    with {:ok, out_links} <- JidoSkillGraph.out_links(graph_id, node_id, link_opts(params, store)) do
      {:ok, out_links, []}
    end
  end

  defp fetch_links(graph_id, node_id, :in, params, store) do
    with {:ok, in_links} <- JidoSkillGraph.in_links(graph_id, node_id, link_opts(params, store)) do
      {:ok, [], in_links}
    end
  end

  defp fetch_links(graph_id, node_id, :both, params, store) do
    with {:ok, out_links} <-
           JidoSkillGraph.out_links(graph_id, node_id, link_opts(params, store)),
         {:ok, in_links} <- JidoSkillGraph.in_links(graph_id, node_id, link_opts(params, store)) do
      {:ok, out_links, in_links}
    end
  end

  defp link_opts(params, store) do
    rel = Map.get(params, "rel") || Map.get(params, :rel)

    [store: store]
    |> maybe_put(:rel, rel)
  end

  defp maybe_add_neighbors(payload, graph_id, node_id, direction, params, store) do
    if boolean_param(params, "include_neighbors", true) do
      hops = integer_param(params, "hops", 1)

      case JidoSkillGraph.neighbors(graph_id, node_id,
             store: store,
             direction: direction,
             hops: hops,
             rel: Map.get(params, "rel") || Map.get(params, :rel)
           ) do
        {:ok, neighbors} -> Map.put(payload, "neighbors", neighbors)
        {:error, _reason} -> Map.put(payload, "neighbors", [])
      end
    else
      payload
    end
  end

  defp required_string(params, key) do
    value = Map.get(params, key)

    if is_binary(value) and String.trim(value) != "" do
      {:ok, String.trim(value)}
    else
      {:error, {:missing_param, key}}
    end
  end

  defp direction_param(params) do
    params
    |> Map.get("direction", "both")
    |> normalize_direction()
  end

  defp normalize_direction(value) when value in ["out", :out], do: {:ok, :out}
  defp normalize_direction(value) when value in ["in", :in], do: {:ok, :in}
  defp normalize_direction(value) when value in ["both", :both], do: {:ok, :both}
  defp normalize_direction(other), do: {:error, {:invalid_direction, other}}

  defp boolean_param(params, key, default) do
    case Map.get(params, key) do
      value when is_boolean(value) -> value
      _ -> default
    end
  end

  defp integer_param(params, key, default) do
    case Map.get(params, key) do
      value when is_integer(value) -> value
      _ -> default
    end
  end

  defp list_param(params, key, default) do
    case Map.get(params, key) do
      value when is_list(value) -> value
      _ -> default
    end
  end

  defp edge_to_map(%Edge{} = edge) do
    %{
      "from" => edge.from,
      "to" => edge.to,
      "rel" => Atom.to_string(edge.rel),
      "label" => edge.label,
      "source_span" => edge.source_span
    }
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp error(reason, message) do
    {:error,
     %{
       "error" => %{
         "code" => error_code(reason),
         "message" => message,
         "details" => inspect(reason)
       }
     }}
  end

  defp error_code(:unknown_tool), do: "UNKNOWN_TOOL"
  defp error_code({:missing_param, _}), do: "INVALID_PARAMS"
  defp error_code({:invalid_direction, _}), do: "INVALID_PARAMS"
  defp error_code({:unknown_graph, _}), do: "UNKNOWN_GRAPH"
  defp error_code({:unknown_node, _}), do: "UNKNOWN_NODE"
  defp error_code({:invalid_relation_filter, _}), do: "INVALID_PARAMS"
  defp error_code(:graph_not_loaded), do: "GRAPH_NOT_LOADED"
  defp error_code(_), do: "INTERNAL_ERROR"

  defp stringify(%{} = value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), stringify(v)} end)
    |> Map.new()
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value
end
