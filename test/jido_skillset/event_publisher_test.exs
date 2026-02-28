defmodule Jido.Skillset.EventPublisherTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Skillset.EventPublisher
  alias Jido.Skillset.JidoAdapter.SignalPublisher

  defmodule ProbePublisher do
    @behaviour Jido.Skillset.EventPublisher

    @impl true
    def publish(event_name, payload, opts) do
      if test_pid = Keyword.get(opts, :test_pid) do
        send(test_pid, {:probe_event, event_name, payload})
      end

      :ok
    end
  end

  test "publish/4 delegates to configured publisher module" do
    assert :ok =
             EventPublisher.publish(
               ProbePublisher,
               "skills_graph.loaded",
               %{graph_id: "basic"},
               test_pid: self()
             )

    assert_receive {:probe_event, "skills_graph.loaded", %{graph_id: "basic"}}
  end

  test "publish/4 returns an error for invalid publisher modules" do
    module = Module.concat(__MODULE__, MissingPublisher)

    assert {:error, {:invalid_event_publisher, ^module}} =
             EventPublisher.publish(module, "skills_graph.loaded", %{}, [])
  end

  test "signal publisher emits telemetry events with merged metadata" do
    handler_id = "signal-publisher-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:jido_skillset, :loaded], [:jido_skillset, :event]],
        &__MODULE__.handle_telemetry/4,
        %{test_pid: self()}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok =
             SignalPublisher.publish(
               "skills_graph.loaded",
               %{graph_id: "basic"},
               metadata: [origin: :test]
             )

    assert_receive {:telemetry_event, [:jido_skillset, :loaded], %{count: 1},
                    %{graph_id: "basic", origin: :test}}
  end

  test "signal publisher publishes to jido_signal bus when configured" do
    bus_name = :"jsg-signal-bus-#{System.unique_integer([:positive])}"
    {:ok, _bus_pid} = Bus.start_link(name: bus_name)
    assert {:ok, _subscription_id} = Bus.subscribe(bus_name, "skills_graph.*")

    assert :ok =
             SignalPublisher.publish(
               "skills_graph.loaded",
               %{graph_id: "basic"},
               bus: bus_name,
               metadata: [origin: :test]
             )

    assert_receive {:signal,
                    %Signal{
                      type: "skills_graph.loaded",
                      data: %{graph_id: "basic", origin: :test},
                      source: "jido_skillset"
                    }}
  end

  def handle_telemetry(event, measurements, metadata, %{test_pid: test_pid}) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end
end
