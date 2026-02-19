defmodule JidoSkillGraph.Loader do
  @moduledoc """
  Snapshot reload coordinator.

  Reload builds a fresh snapshot, then atomically swaps it into `JidoSkillGraph.Store`.
  If build fails, the currently active snapshot remains unchanged.
  """

  use GenServer

  alias JidoSkillGraph.{Builder, Store}

  @type status :: %{
          version: non_neg_integer(),
          last_loaded_at: DateTime.t() | nil,
          last_error: term() | nil,
          builder_opts: keyword(),
          store: GenServer.name()
        }

  @type state :: %{
          store: GenServer.name(),
          builder_opts: keyword(),
          version: non_neg_integer(),
          last_loaded_at: DateTime.t() | nil,
          last_error: term() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec reload(GenServer.name(), keyword()) :: :ok | {:error, term()}
  def reload(server \\ __MODULE__, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:reload, opts}, :infinity)
  end

  @spec status(GenServer.name()) :: status()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @impl true
  def init(opts) do
    state = %{
      store: Keyword.get(opts, :store, Store),
      builder_opts: Keyword.get(opts, :builder_opts, []),
      version: 0,
      last_loaded_at: nil,
      last_error: nil
    }

    if Keyword.get(opts, :load_on_start, true) do
      send(self(), :initial_load)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:initial_load, state) do
    case do_reload([], state) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason, next_state} ->
        {:noreply, %{next_state | last_error: {:initial_load_failed, reason}}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      version: state.version,
      last_loaded_at: state.last_loaded_at,
      last_error: state.last_error,
      builder_opts: state.builder_opts,
      store: state.store
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:reload, opts}, _from, state) do
    case do_reload(opts, state) do
      {:ok, next_state} ->
        {:reply, :ok, %{next_state | last_error: nil}}

      {:error, reason, next_state} ->
        {:reply, {:error, reason}, %{next_state | last_error: reason}}
    end
  end

  defp do_reload(opts, state) do
    build_opts =
      state.builder_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:version, state.version + 1)

    case Builder.build(build_opts) do
      {:ok, snapshot} ->
        case Store.swap_snapshot(state.store, snapshot) do
          {:ok, committed_snapshot} ->
            {:ok,
             %{
               state
               | version: committed_snapshot.version,
                 last_loaded_at: DateTime.utc_now() |> DateTime.truncate(:second)
             }}

          {:error, reason} ->
            {:error, {:store_swap_failed, reason}, state}
        end

      {:error, reason} ->
        {:error, {:build_failed, reason}, state}
    end
  end
end
