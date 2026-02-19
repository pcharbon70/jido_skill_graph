defmodule JidoSkillGraph.Builder do
  @moduledoc """
  Build pipeline entrypoint: discover -> parse -> extract -> resolve -> snapshot.

  Phase 3 establishes strict model contracts and unresolved-link policy
  handling for snapshots.
  """

  alias JidoSkillGraph.Snapshot

  @type snapshot :: Snapshot.t()

  @spec build(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def build(opts \\ []) do
    Snapshot.new(
      graph: nil,
      graph_id: Keyword.get(opts, :graph_id, "default"),
      version: 0,
      nodes: [],
      edges: [],
      unresolved_link_policy: Keyword.get(opts, :unresolved_link_policy, :warn_and_skip),
      stats: %{mode: :pure}
    )
  end
end
