defmodule Jido.Skillset do
  @moduledoc """
  Facade and supervisor entrypoint for the standalone skill graph library.

  Phase 2 focuses on package bootstrap and public architecture shape.
  Core graph behavior is implemented incrementally in later phases.
  """

  use Supervisor

  alias Jido.Skillset.{Builder, EventPublisher, Loader, Query, Store, Telemetry, Watcher}
  alias Jido.Skillset.EventPublisher.Noop, as: NoopPublisher

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
    store_name = Keyword.get(store_opts, :name, Jido.Skillset.Store)

    loader_opts =
      opts
      |> Keyword.get(:loader, [])
      |> Keyword.put_new(:store, store_name)

    loader_name = Keyword.get(loader_opts, :name, Jido.Skillset.Loader)

    watcher_opts =
      opts
      |> Keyword.get(:watcher, [])
      |> Keyword.put_new(:loader, loader_name)
      |> Keyword.put_new(:root, Keyword.get(loader_opts, :root, "."))

    children =
      [
        {Jido.Skillset.Store, store_opts},
        {Jido.Skillset.Loader, loader_opts}
      ]
      |> maybe_add_watcher(opts, watcher_opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Builds a snapshot struct without starting supervised processes.
  """
  @spec build(keyword()) :: {:ok, Builder.snapshot()} | {:error, term()}
  def build(opts \\ []) do
    Builder.build(opts)
  end

  @doc """
  Returns the active snapshot from the running store process.
  """
  @spec current_snapshot(GenServer.name()) :: Builder.snapshot() | nil
  def current_snapshot(server \\ Store) do
    Store.current_snapshot(server)
  end

  @doc """
  Triggers a loader refresh cycle.
  """
  @spec reload(GenServer.name(), keyword()) :: :ok | {:error, term()}
  def reload(server \\ Loader, opts \\ []) do
    Loader.reload(server, opts)
  end

  @doc """
  Lists loaded graph identifiers from the current snapshot.
  """
  @spec list_graphs(keyword()) :: [String.t()]
  def list_graphs(opts \\ []) do
    opts
    |> snapshot_from_opts()
    |> Query.list_graphs()
  end

  @doc """
  Returns graph topology metadata for the requested graph.
  """
  @spec topology(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def topology(graph_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.topology(snapshot, graph_id, opts)
    end)
  end

  @doc """
  Lists node metadata for a graph.
  """
  @spec list_nodes(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_nodes(graph_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.list_nodes(snapshot, graph_id, opts)
    end)
  end

  @doc """
  Returns metadata for a specific node.
  """
  @spec get_node_meta(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_node_meta(graph_id, node_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.get_node_meta(snapshot, graph_id, node_id)
    end)
  end

  @doc """
  Reads node body content on demand.
  """
  @spec read_node_body(String.t(), String.t(), keyword()) ::
          {:ok, String.t() | map()} | {:error, term()}
  def read_node_body(graph_id, node_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      case Query.read_node_body(snapshot, graph_id, node_id, opts) do
        {:ok, payload} = result ->
          emit_node_read_telemetry(snapshot, graph_id, node_id, payload, :ok, opts)
          publish_node_read_event(snapshot, graph_id, node_id, payload, opts)
          result

        error ->
          emit_node_read_telemetry(snapshot, graph_id, node_id, nil, error, opts)
          error
      end
    end)
  end

  @doc """
  Lists outbound links for a node.
  """
  @spec out_links(String.t(), String.t(), keyword()) ::
          {:ok, [Jido.Skillset.Edge.t()]} | {:error, term()}
  def out_links(graph_id, node_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.out_links(snapshot, graph_id, node_id, opts)
    end)
  end

  @doc """
  Lists inbound links for a node.
  """
  @spec in_links(String.t(), String.t(), keyword()) ::
          {:ok, [Jido.Skillset.Edge.t()]} | {:error, term()}
  def in_links(graph_id, node_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.in_links(snapshot, graph_id, node_id, opts)
    end)
  end

  @doc """
  Returns neighbor node ids reachable from a source node.
  """
  @spec neighbors(String.t(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def neighbors(graph_id, node_id, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.neighbors(snapshot, graph_id, node_id, opts)
    end)
  end

  @doc """
  Searches nodes in a graph using the configured search backend.
  """
  @spec search(String.t(), String.t(), keyword()) ::
          {:ok, [Jido.Skillset.SearchBackend.result()]} | {:error, term()}
  def search(graph_id, query, opts \\ []) do
    with_snapshot(opts, fn snapshot ->
      Query.search(snapshot, graph_id, query, opts)
    end)
  end

  defp with_snapshot(opts, callback) when is_function(callback, 1) do
    case snapshot_from_opts(opts) do
      nil -> {:error, :graph_not_loaded}
      snapshot -> callback.(snapshot)
    end
  end

  defp snapshot_from_opts(opts) do
    store = Keyword.get(opts, :store, Store)
    current_snapshot(store)
  end

  defp maybe_add_watcher(children, opts, watcher_opts) do
    if Keyword.get(opts, :watch?, false) do
      children ++ [{Watcher, watcher_opts}]
    else
      children
    end
  end

  defp publish_node_read_event(snapshot, graph_id, node_id, payload, opts) do
    event_publisher = Keyword.get(opts, :event_publisher, NoopPublisher)
    event_publisher_opts = Keyword.get(opts, :event_publisher_opts, [])

    metadata = %{
      graph_id: graph_id,
      node_id: node_id,
      version: snapshot.version,
      with_frontmatter: Keyword.get(opts, :with_frontmatter, false),
      trim: Keyword.get(opts, :trim, false),
      bytes: payload_size(payload)
    }

    _ =
      EventPublisher.publish(
        event_publisher,
        "skills_graph.node_read",
        metadata,
        event_publisher_opts
      )

    :ok
  end

  defp payload_size(%{body: body}) when is_binary(body), do: byte_size(body)
  defp payload_size(payload) when is_binary(payload), do: byte_size(payload)
  defp payload_size(_payload), do: 0

  defp emit_node_read_telemetry(snapshot, graph_id, node_id, payload, status, opts) do
    metadata = %{
      graph_id: graph_id,
      node_id: node_id,
      version: snapshot.version,
      status: normalize_read_status(status),
      with_frontmatter: Keyword.get(opts, :with_frontmatter, false),
      trim: Keyword.get(opts, :trim, false)
    }

    measurements = %{
      count: 1,
      bytes: payload_size(payload)
    }

    Telemetry.execute([:query, :node_read], measurements, metadata)
  end

  defp normalize_read_status(:ok), do: :ok
  defp normalize_read_status({:error, _reason}), do: :error
end
