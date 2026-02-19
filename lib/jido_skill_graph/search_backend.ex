defmodule JidoSkillGraph.SearchBackend do
  @moduledoc """
  Search backend behavior for pluggable query implementations.
  """

  @callback search(snapshot :: term(), graph_id :: term(), query :: term(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, term()}
end
