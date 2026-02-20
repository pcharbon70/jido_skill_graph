defmodule JidoSkillGraph.MCP do
  @moduledoc """
  Compatibility facade for MCP tools/resources.

  New code should use `JidoSkillGraphMCP`.
  """

  @spec tool_definitions() :: [map()]
  defdelegate tool_definitions(), to: JidoSkillGraphMCP

  @spec call_tool(String.t(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate call_tool(name, params \\ %{}, opts \\ []), to: JidoSkillGraphMCP

  @spec resource_templates() :: [map()]
  defdelegate resource_templates(), to: JidoSkillGraphMCP

  @spec read_resource(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate read_resource(uri, opts \\ []), to: JidoSkillGraphMCP
end
