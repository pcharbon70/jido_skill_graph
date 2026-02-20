defmodule JidoSkillGraphMCP do
  @moduledoc """
  Standalone-ready MCP facade for tools and resources.

  This module is designed to match the package boundary that can live in a
  dedicated `jido_skill_graph_mcp` package.
  """

  alias JidoSkillGraphMCP.{Resources, Tools}

  @spec tool_definitions() :: [map()]
  def tool_definitions, do: Tools.definitions()

  @spec call_tool(String.t(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  def call_tool(name, params \\ %{}, opts \\ []), do: Tools.call(name, params, opts)

  @spec resource_templates() :: [map()]
  def resource_templates, do: Resources.templates()

  @spec read_resource(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def read_resource(uri, opts \\ []), do: Resources.read(uri, opts)
end
