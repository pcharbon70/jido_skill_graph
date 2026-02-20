defmodule JidoSkillGraph.MCP.Resources do
  @moduledoc """
  Compatibility layer for MCP resource handlers.

  New code should use `JidoSkillGraphMCP.Resources`.
  """

  @spec templates() :: [map()]
  defdelegate templates(), to: JidoSkillGraphMCP.Resources

  @spec parse_uri(String.t()) ::
          {:ok, %{graph_id: String.t(), node_id: String.t()}} | {:error, term()}
  defdelegate parse_uri(uri), to: JidoSkillGraphMCP.Resources

  @spec read(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate read(uri, opts \\ []), to: JidoSkillGraphMCP.Resources
end
