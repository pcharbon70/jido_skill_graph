defmodule JidoSkillGraph.Store do
  @moduledoc """
  In-memory snapshot holder.

  Later phases add ETS-backed graph/node/edge indexing and atomic swap semantics.
  """

  use GenServer

  @type state :: %{snapshot: JidoSkillGraph.Builder.snapshot() | nil}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec current_snapshot(GenServer.name()) :: JidoSkillGraph.Builder.snapshot() | nil
  def current_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :current_snapshot)
  end

  @spec swap_snapshot(GenServer.name(), JidoSkillGraph.Builder.snapshot()) :: :ok
  def swap_snapshot(server \\ __MODULE__, snapshot) do
    GenServer.call(server, {:swap_snapshot, snapshot})
  end

  @impl true
  def init(_opts) do
    {:ok, %{snapshot: nil}}
  end

  @impl true
  def handle_call(:current_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_call({:swap_snapshot, snapshot}, _from, state) do
    {:reply, :ok, %{state | snapshot: snapshot}}
  end
end
