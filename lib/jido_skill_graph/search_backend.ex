defmodule JidoSkillGraph.SearchBackend do
  @moduledoc """
  Search backend behavior for pluggable query implementations.
  """

  alias JidoSkillGraph.Snapshot

  @type result :: %{
          required(:id) => String.t(),
          required(:score) => non_neg_integer(),
          optional(:title) => String.t() | nil,
          optional(:path) => Path.t(),
          optional(:tags) => [String.t()],
          optional(:matches) => [atom()],
          optional(:excerpt) => String.t() | nil
        }

  @callback search(
              snapshot :: Snapshot.t(),
              graph_id :: String.t(),
              query :: String.t(),
              opts :: keyword()
            ) :: {:ok, [result()]} | {:error, term()}
end
