defmodule JidoSkillGraph do
  @moduledoc """
  Facade and supervisor entrypoint for the standalone skill graph library.

  Phase 2 focuses on package bootstrap and public architecture shape.
  Core graph behavior is implemented incrementally in later phases.
  """

  use Supervisor

  @type start_option ::
          {:name, GenServer.name()}
          | {:store, keyword()}
          | {:loader, keyword()}
          | {:watcher, keyword()}
          | {:watch?, boolean()}

  @spec start_link([start_option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    children =
      [
        {JidoSkillGraph.Store, Keyword.get(opts, :store, [])},
        {JidoSkillGraph.Loader, Keyword.get(opts, :loader, [])}
      ]
      |> maybe_add_watcher(opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Builds a snapshot struct without starting supervised processes.
  """
  @spec build(keyword()) :: {:ok, JidoSkillGraph.Builder.snapshot()} | {:error, term()}
  def build(opts \\ []) do
    JidoSkillGraph.Builder.build(opts)
  end

  @doc """
  Returns the active snapshot from the running store process.
  """
  @spec current_snapshot(GenServer.name()) :: JidoSkillGraph.Builder.snapshot() | nil
  def current_snapshot(server \\ JidoSkillGraph.Store) do
    JidoSkillGraph.Store.current_snapshot(server)
  end

  @doc """
  Triggers a loader refresh cycle.
  """
  @spec reload(GenServer.name()) :: :ok | {:error, term()}
  def reload(server \\ JidoSkillGraph.Loader) do
    JidoSkillGraph.Loader.reload(server)
  end

  defp maybe_add_watcher(children, opts) do
    if Keyword.get(opts, :watch?, false) do
      children ++ [{JidoSkillGraph.Watcher, Keyword.get(opts, :watcher, [])}]
    else
      children
    end
  end
end
