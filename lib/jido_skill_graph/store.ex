defmodule JidoSkillGraph.Store do
  @moduledoc """
  In-memory snapshot holder with atomic publish semantics.

  Snapshots are published to `:persistent_term` so readers can access the current
  snapshot without blocking on the GenServer process.
  """

  use GenServer

  alias JidoSkillGraph.Snapshot

  @type state :: %{
          name: GenServer.name() | nil,
          persistent_key: term(),
          snapshot: Snapshot.t() | nil,
          version: non_neg_integer(),
          updated_at: DateTime.t() | nil
        }

  @type metadata :: %{
          version: non_neg_integer(),
          updated_at: DateTime.t() | nil,
          persistent_key: term()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec current_snapshot(GenServer.name()) :: Snapshot.t() | nil
  def current_snapshot(server \\ __MODULE__) do
    case persistent_key_for(server) do
      {:ok, key} -> :persistent_term.get(key, nil)
      :unknown -> GenServer.call(server, :current_snapshot)
    end
  end

  @spec swap_snapshot(GenServer.name(), Snapshot.t()) :: {:ok, Snapshot.t()} | {:error, term()}
  def swap_snapshot(server \\ __MODULE__, %Snapshot{} = snapshot) do
    GenServer.call(server, {:swap_snapshot, snapshot})
  end

  @spec metadata(GenServer.name()) :: metadata()
  def metadata(server \\ __MODULE__) do
    GenServer.call(server, :metadata)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    persistent_key = Keyword.get(opts, :persistent_key, persistent_key(name))

    state = %{
      name: name,
      persistent_key: persistent_key,
      snapshot: nil,
      version: 0,
      updated_at: nil
    }

    :persistent_term.put(persistent_key, nil)

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    :persistent_term.erase(state.persistent_key)
    :ok
  end

  @impl true
  def handle_call(:current_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_call(:metadata, _from, state) do
    {:reply,
     %{
       version: state.version,
       updated_at: state.updated_at,
       persistent_key: state.persistent_key
     }, state}
  end

  @impl true
  def handle_call({:swap_snapshot, %Snapshot{} = snapshot}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    next_snapshot =
      if snapshot.version < state.version do
        %{snapshot | version: state.version + 1}
      else
        snapshot
      end

    next_state = %{
      state
      | snapshot: next_snapshot,
        version: next_snapshot.version,
        updated_at: now
    }

    :persistent_term.put(state.persistent_key, next_snapshot)

    {:reply, {:ok, next_snapshot}, next_state}
  end

  @spec persistent_key(GenServer.name()) :: term()
  def persistent_key(name), do: {__MODULE__, name, :snapshot}

  defp persistent_key_for(name) when is_atom(name) or is_tuple(name),
    do: {:ok, persistent_key(name)}

  defp persistent_key_for(_name), do: :unknown
end
