defmodule JidoSkillGraph.MCP.Tools do
  @moduledoc """
  Compatibility layer for MCP tool handlers.

  New code should use `JidoSkillGraphMCP.Tools`.
  """

  @spec definitions() :: [map()]
  defdelegate definitions(), to: JidoSkillGraphMCP.Tools

  @spec call(String.t(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate call(name, params \\ %{}, opts \\ []), to: JidoSkillGraphMCP.Tools
end
