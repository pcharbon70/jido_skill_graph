defmodule JidoSkillGraph.Watcher do
  @moduledoc """
  Optional file watcher process for automatic reload triggers.

  This watcher debounces filesystem events and triggers `JidoSkillGraph.Loader.reload/2`.
  """

  use GenServer

  alias JidoSkillGraph.Loader

  @type state :: %{
          loader: GenServer.name(),
          root: Path.t(),
          debounce_ms: non_neg_integer(),
          watcher_pid: pid() | nil,
          timer_ref: reference() | nil,
          supported?: boolean()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    root = opts |> Keyword.get(:root, ".") |> Path.expand()
    debounce_ms = Keyword.get(opts, :debounce_ms, 250)
    loader = Keyword.get(opts, :loader, Loader)

    with true <- Code.ensure_loaded?(FileSystem),
         {:ok, watcher_pid} <- FileSystem.start_link(dirs: [root]) do
      FileSystem.subscribe(watcher_pid)

      {:ok,
       %{
         loader: loader,
         root: root,
         debounce_ms: debounce_ms,
         watcher_pid: watcher_pid,
         timer_ref: nil,
         supported?: true
       }}
    else
      _ ->
        {:ok,
         %{
           loader: loader,
           root: root,
           debounce_ms: debounce_ms,
           watcher_pid: nil,
           timer_ref: nil,
           supported?: false
         }}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    if should_reload?(path, events) do
      {:noreply, schedule_reload(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state), do: {:noreply, state}

  @impl true
  def handle_info(:reload, state) do
    _ = Loader.reload(state.loader)
    {:noreply, %{state | timer_ref: nil}}
  end

  defp should_reload?(path, events) do
    path = to_string(path)

    interesting_file? =
      String.ends_with?(path, "SKILL.md") or
        String.ends_with?(path, "skill.md") or
        String.ends_with?(path, "graph.yml")

    event_hit? = Enum.any?(events, &(&1 in [:created, :modified, :deleted, :renamed]))

    interesting_file? and event_hit?
  end

  defp schedule_reload(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    ref = Process.send_after(self(), :reload, state.debounce_ms)
    %{state | timer_ref: ref}
  end
end
