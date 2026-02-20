defmodule JidoSkillGraph.JidoAdapter do
  @moduledoc """
  Optional integration helpers for wiring JidoSkillGraph into Jido runtimes.

  This module intentionally does not depend on Jido directly.
  """

  alias JidoSkillGraph.JidoAdapter.SignalPublisher

  @type option ::
          {:id, term()}
          | {:name, GenServer.name()}
          | {:store, keyword()}
          | {:loader, keyword()}
          | {:watcher, keyword()}
          | {:watch?, boolean()}
          | {:event_publisher, module()}
          | {:event_publisher_opts, keyword()}

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    event_publisher = Keyword.get(opts, :event_publisher, SignalPublisher)
    event_publisher_opts = Keyword.get(opts, :event_publisher_opts, [])

    loader_opts =
      opts
      |> Keyword.get(:loader, [])
      |> Keyword.put_new(:event_publisher, event_publisher)
      |> Keyword.put_new(:event_publisher_opts, event_publisher_opts)

    graph_opts =
      opts
      |> Keyword.take([:name, :store, :watcher, :watch?])
      |> Keyword.put(:loader, loader_opts)

    child = {JidoSkillGraph, graph_opts}

    case Keyword.fetch(opts, :id) do
      {:ok, id} -> Supervisor.child_spec(child, id: id)
      :error -> Supervisor.child_spec(child, [])
    end
  end

  @spec read_node_body(String.t(), String.t(), keyword()) ::
          {:ok, String.t() | map()} | {:error, term()}
  def read_node_body(graph_id, node_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:event_publisher, SignalPublisher)
      |> Keyword.put_new(:event_publisher_opts, [])

    JidoSkillGraph.read_node_body(graph_id, node_id, opts)
  end
end
