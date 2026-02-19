defmodule JidoSkillGraph.Watcher do
  @moduledoc """
  Optional file watcher process for automatic reload triggers.

  Later phases integrate filesystem subscriptions and debounce logic.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
end
