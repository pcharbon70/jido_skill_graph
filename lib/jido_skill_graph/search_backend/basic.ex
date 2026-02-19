defmodule JidoSkillGraph.SearchBackend.Basic do
  @moduledoc """
  Baseline no-op search backend.

  Later phases provide metadata/body matching behavior.
  """

  @behaviour JidoSkillGraph.SearchBackend

  @impl true
  def search(_snapshot, _graph_id, _query, _opts) do
    {:ok, []}
  end
end
