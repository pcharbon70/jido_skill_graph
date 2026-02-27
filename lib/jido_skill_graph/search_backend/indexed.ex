defmodule JidoSkillGraph.SearchBackend.Indexed do
  @moduledoc """
  Indexed backend entry point used for phased rollout.

  Phase 0 delegates to `JidoSkillGraph.SearchBackend.Basic` while index
  structures are introduced in later phases.
  """

  @behaviour JidoSkillGraph.SearchBackend

  alias JidoSkillGraph.SearchBackend.Basic
  alias JidoSkillGraph.Snapshot

  @impl true
  def search(%Snapshot{} = snapshot, graph_id, query, opts) do
    Basic.search(snapshot, graph_id, query, opts)
  end
end
