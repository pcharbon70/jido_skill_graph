defmodule JidoSkillGraph.MCP.Resources do
  @moduledoc """
  MCP resource handlers for `skill://<graph_id>/<node_id>` URIs.
  """

  @spec templates() :: [map()]
  def templates do
    [
      %{
        "uriTemplate" => "skill://{graph_id}/{node_id}",
        "name" => "skill-node",
        "description" => "Read node markdown body by graph and node id.",
        "mimeType" => "text/markdown"
      }
    ]
  end

  @spec parse_uri(String.t()) ::
          {:ok, %{graph_id: String.t(), node_id: String.t()}} | {:error, term()}
  def parse_uri(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "skill", host: graph_id, path: path}
      when is_binary(graph_id) and graph_id != "" and is_binary(path) and path != "" ->
        node_id = String.trim_leading(path, "/")

        if node_id == "" do
          {:error, :missing_node_id}
        else
          {:ok, %{graph_id: graph_id, node_id: node_id}}
        end

      %URI{scheme: "skill"} ->
        {:error, :invalid_skill_uri}

      _ ->
        {:error, :unsupported_scheme}
    end
  end

  @spec read(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def read(uri, opts \\ []) when is_binary(uri) do
    store = Keyword.get(opts, :store, JidoSkillGraph.Store)

    with {:ok, %{graph_id: graph_id, node_id: node_id}} <- parse_uri(uri),
         {:ok, content} <- JidoSkillGraph.read_node_body(graph_id, node_id, store: store) do
      {:ok,
       %{
         "uri" => uri,
         "mimeType" => "text/markdown",
         "text" => content,
         "graph_id" => graph_id,
         "node_id" => node_id
       }}
    else
      {:error, reason} ->
        {:error,
         %{
           "error" => %{
             "code" => error_code(reason),
             "message" => "Failed to read MCP resource",
             "details" => inspect(reason)
           }
         }}
    end
  end

  defp error_code(:unsupported_scheme), do: "UNSUPPORTED_URI_SCHEME"
  defp error_code(:missing_node_id), do: "INVALID_RESOURCE_URI"
  defp error_code(:invalid_skill_uri), do: "INVALID_RESOURCE_URI"
  defp error_code({:unknown_graph, _}), do: "UNKNOWN_GRAPH"
  defp error_code({:unknown_node, _}), do: "UNKNOWN_NODE"
  defp error_code(:graph_not_loaded), do: "GRAPH_NOT_LOADED"
  defp error_code(_), do: "INTERNAL_ERROR"
end
