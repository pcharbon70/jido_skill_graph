defmodule JidoSkillGraph.Manifest do
  @moduledoc """
  Manifest contract for skill graph discovery metadata.

  Full parsing/validation is implemented in later phases.
  """

  @enforce_keys [:path]
  defstruct [:path, :graph_id, :root, includes: [], metadata: %{}]

  @type t :: %__MODULE__{
          path: Path.t(),
          graph_id: String.t() | nil,
          root: Path.t() | nil,
          includes: [Path.t()],
          metadata: map()
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) when is_binary(path) do
    {:ok, %__MODULE__{path: path}}
  end
end
