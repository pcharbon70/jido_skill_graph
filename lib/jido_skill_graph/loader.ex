defmodule JidoSkillGraph.Loader do
  @moduledoc """
  Snapshot reload coordinator.

  Later phases add asynchronous reload jobs and atomic store swaps.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec reload(GenServer.name()) :: :ok | {:error, term()}
  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end
end
