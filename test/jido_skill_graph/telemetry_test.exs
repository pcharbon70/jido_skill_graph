defmodule JidoSkillGraph.TelemetryTest do
  use ExUnit.Case, async: false

  alias JidoSkillGraph.{Loader, Store}

  test "loader and store emit telemetry for reload success and failure" do
    _handler_id =
      attach_handler([
        [:jido_skill_graph, :loader, :reload],
        [:jido_skill_graph, :store, :snapshot_swap]
      ])

    store_name = unique_name(:store)
    loader_name = unique_name(:loader)
    graph_id = "telemetry-#{System.unique_integer([:positive])}"
    store_ref = inspect(store_name)

    start_supervised!({Store, name: store_name})

    start_supervised!(
      {Loader,
       name: loader_name,
       store: store_name,
       load_on_start: false,
       builder_opts: [root: fixture_path("basic"), graph_id: graph_id]}
    )

    assert :ok = Loader.reload(loader_name)

    assert_receive {:telemetry_event, [:jido_skill_graph, :store, :snapshot_swap], measurements,
                    %{status: :ok, graph_id: ^graph_id, version: 1, node_count: 2, edge_count: 2}}

    assert measurements.count == 1
    assert measurements.duration_ms >= 0

    assert_receive {:telemetry_event, [:jido_skill_graph, :loader, :reload], measurements,
                    %{status: :ok, graph_id: ^graph_id, version: 1, store: ^store_ref}}

    assert measurements.count == 1
    assert measurements.duration_ms >= 0

    assert {:error, {:build_failed, {:invalid_frontmatter, _path, _reason}}} =
             Loader.reload(loader_name,
               root: fixture_path("malformed_frontmatter"),
               graph_id: graph_id
             )

    assert_receive {:telemetry_event, [:jido_skill_graph, :loader, :reload], fail_measurements,
                    %{status: :error, store: ^store_ref, reason: reason}}

    assert fail_measurements.count == 1
    assert fail_measurements.duration_ms >= 0
    assert String.contains?(reason, "build_failed")
  end

  test "query node reads emit telemetry for success and failure" do
    _handler_id = attach_handler([[:jido_skill_graph, :query, :node_read]])
    graph_id = "telemetry-query-#{System.unique_integer([:positive])}"

    {store_name, _loader_name} = load_graph("basic", graph_id)

    assert {:ok, _body} =
             JidoSkillGraph.read_node_body(graph_id, "alpha",
               store: store_name,
               with_frontmatter: false,
               trim: true
             )

    assert_receive {:telemetry_event, [:jido_skill_graph, :query, :node_read],
                    %{count: 1, bytes: bytes},
                    %{
                      status: :ok,
                      graph_id: ^graph_id,
                      node_id: "alpha",
                      with_frontmatter: false,
                      trim: true
                    }}

    assert bytes > 0

    assert {:error, {:unknown_node, "missing"}} =
             JidoSkillGraph.read_node_body(graph_id, "missing",
               store: store_name,
               with_frontmatter: true,
               trim: false
             )

    assert_receive {:telemetry_event, [:jido_skill_graph, :query, :node_read],
                    %{count: 1, bytes: 0},
                    %{
                      status: :error,
                      graph_id: ^graph_id,
                      node_id: "missing",
                      with_frontmatter: true,
                      trim: false
                    }}
  end

  def handle_telemetry(event, measurements, metadata, %{test_pid: test_pid}) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp attach_handler(events) do
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry/4,
        %{test_pid: self()}
      )

    on_exit(fn -> detach_handler(handler_id) end)
    handler_id
  end

  defp detach_handler(handler_id) do
    :telemetry.detach(handler_id)
    :ok
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
