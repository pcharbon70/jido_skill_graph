defmodule Jido.Skillset.JidoAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Skillset.{JidoAdapter, Loader, Store}
  alias Jido.Skillset.JidoAdapter.SignalPublisher

  defmodule TestPublisher do
    @behaviour Jido.Skillset.EventPublisher

    @impl true
    def publish(event_name, payload, opts) do
      if test_pid = Keyword.get(opts, :test_pid) do
        send(test_pid, {:published_event, event_name, payload})
      end

      :ok
    end
  end

  test "child_spec injects signal publisher into loader by default" do
    graph_name = unique_name(:graph)
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!(
      JidoAdapter.child_spec(
        id: unique_name(:child),
        name: graph_name,
        store: [name: store_name],
        loader: [
          name: loader_name,
          load_on_start: false,
          builder_opts: [root: fixture_path("basic"), graph_id: "basic"]
        ]
      )
    )

    assert %{event_publisher: SignalPublisher} = Loader.status(loader_name)
  end

  test "loader publishes loaded and reloaded events" do
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: true,
       builder_opts: [root: fixture_path("basic"), graph_id: "basic"],
       event_publisher: TestPublisher,
       event_publisher_opts: [test_pid: self()]}
    )

    assert_receive {:published_event, "skills_graph.loaded", loaded_payload}
    assert loaded_payload.graph_id == "basic"
    assert loaded_payload.version == 1

    assert :ok = Loader.reload(loader_name)

    assert_receive {:published_event, "skills_graph.reloaded", reloaded_payload}
    assert reloaded_payload.graph_id == "basic"
    assert reloaded_payload.version == 2
  end

  test "adapter read_node_body/3 emits node_read event" do
    {store_name, _loader_name} = load_graph("basic", "basic")

    assert {:ok, body} =
             JidoAdapter.read_node_body("basic", "alpha",
               store: store_name,
               event_publisher: TestPublisher,
               event_publisher_opts: [test_pid: self()]
             )

    assert String.contains?(body, "Alpha")

    assert_receive {:published_event, "skills_graph.node_read", payload}
    assert payload.graph_id == "basic"
    assert payload.node_id == "alpha"
    assert payload.version == 1
    assert payload.bytes > 0
  end

  defp load_graph(fixture, graph_id) do
    store_name = unique_name(:store)
    loader_name = unique_name(:loader)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: false,
       builder_opts: [root: fixture_path(fixture), graph_id: graph_id]}
    )

    assert :ok = Loader.reload(loader_name)
    {store_name, loader_name}
  end

  defp unique_name(kind), do: {:global, {__MODULE__, kind, make_ref()}}

  defp fixture_path(name) do
    Path.expand("../fixtures/phase4/#{name}", __DIR__)
  end
end
