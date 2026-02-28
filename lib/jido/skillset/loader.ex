defmodule Jido.Skillset.Loader do
  @moduledoc """
  Snapshot reload coordinator.

  Reload builds a fresh snapshot, then atomically swaps it into `Jido.Skillset.Store`.
  If build fails, the currently active snapshot remains unchanged.
  """

  use GenServer

  alias Jido.Skillset.{Builder, EventPublisher, Store, Telemetry}
  alias Jido.Skillset.EventPublisher.Noop, as: NoopPublisher

  @type status :: %{
          version: non_neg_integer(),
          last_loaded_at: DateTime.t() | nil,
          last_error: term() | nil,
          builder_opts: keyword(),
          store: GenServer.name(),
          event_publisher: module()
        }

  @type state :: %{
          store: GenServer.name(),
          builder_opts: keyword(),
          version: non_neg_integer(),
          last_loaded_at: DateTime.t() | nil,
          last_error: term() | nil,
          event_publisher: module(),
          event_publisher_opts: keyword()
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
      last_error: nil,
      event_publisher: Keyword.get(opts, :event_publisher, NoopPublisher),
      event_publisher_opts: Keyword.get(opts, :event_publisher_opts, [])
    }

    if Keyword.get(opts, :load_on_start, true) do
      send(self(), :initial_load)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:initial_load, state) do
    case do_reload([], state, "skills_graph.loaded") do
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
      store: state.store,
      event_publisher: state.event_publisher
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:reload, opts}, _from, state) do
    case do_reload(opts, state, "skills_graph.reloaded") do
      {:ok, next_state} ->
        {:reply, :ok, %{next_state | last_error: nil}}

      {:error, reason, next_state} ->
        {:reply, {:error, reason}, %{next_state | last_error: reason}}
    end
  end

  defp do_reload(opts, state, event_name) do
    started_at = System.monotonic_time()

    build_opts =
      state.builder_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:version, state.version + 1)

    case Builder.build(build_opts) do
      {:ok, snapshot} ->
        case Store.swap_snapshot(state.store, snapshot) do
          {:ok, committed_snapshot} ->
            publish_event(state, event_name, committed_snapshot)
            emit_reload_telemetry(started_at, :ok, committed_snapshot, state.store)

            {:ok,
             %{
               state
               | version: committed_snapshot.version,
                 last_loaded_at: DateTime.utc_now() |> DateTime.truncate(:second)
             }}

          {:error, reason} ->
            emit_reload_failure_telemetry(started_at, {:store_swap_failed, reason}, state.store)
            {:error, {:store_swap_failed, reason}, state}
        end

      {:error, reason} ->
        emit_reload_failure_telemetry(started_at, {:build_failed, reason}, state.store)
        {:error, {:build_failed, reason}, state}
    end
  end

  defp publish_event(state, event_name, snapshot) do
    payload = %{
      graph_id: snapshot.graph_id,
      version: snapshot.version,
      warnings: length(snapshot.warnings),
      stats: snapshot.stats
    }

    _ =
      EventPublisher.publish(
        state.event_publisher,
        event_name,
        payload,
        state.event_publisher_opts
      )

    :ok
  end

  defp emit_reload_telemetry(started_at, status, snapshot, store) do
    metadata = %{
      status: status,
      graph_id: snapshot.graph_id,
      version: snapshot.version,
      warning_count: length(snapshot.warnings),
      store: inspect(store)
    }

    emit_loader_telemetry(started_at, metadata)
  end

  defp emit_reload_failure_telemetry(started_at, reason, store) do
    metadata = %{
      status: :error,
      reason: inspect(reason),
      store: inspect(store)
    }

    emit_loader_telemetry(started_at, metadata)
  end

  defp emit_loader_telemetry(started_at, metadata) do
    duration_native = System.monotonic_time() - started_at

    Telemetry.execute(
      [:loader, :reload],
      Telemetry.duration_measurements(duration_native),
      metadata
    )
  end
end
