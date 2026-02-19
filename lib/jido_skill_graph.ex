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
    store_opts = Keyword.get(opts, :store, [])
    store_name = Keyword.get(store_opts, :name, JidoSkillGraph.Store)

    loader_opts =
      opts
      |> Keyword.get(:loader, [])
      |> Keyword.put_new(:store, store_name)

    loader_name = Keyword.get(loader_opts, :name, JidoSkillGraph.Loader)

    watcher_opts =
      opts
      |> Keyword.get(:watcher, [])
      |> Keyword.put_new(:loader, loader_name)
      |> Keyword.put_new(:root, Keyword.get(loader_opts, :root, "."))

    children =
      [
        {JidoSkillGraph.Store, store_opts},
        {JidoSkillGraph.Loader, loader_opts}
      ]
      |> maybe_add_watcher(opts, watcher_opts)

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
  @spec reload(GenServer.name(), keyword()) :: :ok | {:error, term()}
  def reload(server \\ JidoSkillGraph.Loader, opts \\ []) do
    JidoSkillGraph.Loader.reload(server, opts)
  end

  defp maybe_add_watcher(children, opts, watcher_opts) do
    if Keyword.get(opts, :watch?, false) do
      children ++ [{JidoSkillGraph.Watcher, watcher_opts}]
    else
      children
    end
  end
end
