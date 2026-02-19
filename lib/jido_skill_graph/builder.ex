defmodule JidoSkillGraph.Builder do
  @moduledoc """
  Build pipeline entrypoint: discover -> parse -> extract -> resolve -> snapshot.

  Phase 2 returns a placeholder snapshot shape so downstream modules
  can integrate incrementally.
  """

  @type snapshot :: %{
          mode: :pure,
          graph: nil,
          nodes: list(),
          edges: list(),
          version: non_neg_integer(),
          opts: keyword()
        }

  @spec build(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def build(opts \\ []) do
    {:ok,
     %{
       mode: :pure,
       graph: nil,
       nodes: [],
       edges: [],
       version: 0,
       opts: opts
     }}
  end
end
