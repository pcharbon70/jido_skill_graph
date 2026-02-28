defmodule JidoSkillGraph.JidoAdapter.SignalPublisher do
  @moduledoc """
  Event publisher that emits telemetry and optionally publishes to `jido_signal`.

  Pass `bus: ...` in `event_publisher_opts` to publish `Jido.Signal` events to
  a bus managed by `jido_signal`.
  """

  @behaviour JidoSkillGraph.EventPublisher

  alias Jido.Signal
  alias Jido.Signal.Bus

  @impl true
  def publish(event_name, payload, opts) do
    metadata = Map.merge(payload, Map.new(Keyword.get(opts, :metadata, [])))

    _ = maybe_publish_jido_signal(event_name, metadata, opts)
    _ = emit_telemetry(event_name, metadata)

    :ok
  end

  defp maybe_publish_jido_signal(event_name, metadata, opts) do
    case Keyword.get(opts, :bus) do
      nil ->
        :ok

      bus ->
        with {:ok, signal} <- Signal.new(event_name, metadata, source: "jido_skill_graph"),
             {:ok, _recorded_signals} <- Bus.publish(bus, [signal]) do
          :ok
        else
          {:error, reason} -> {:error, {:jido_signal_publish_failed, reason}}
        end
    end
  end

  defp emit_telemetry(event_name, metadata) do
    :telemetry.execute(telemetry_event(event_name), %{count: 1}, metadata)
  end

  defp telemetry_event("skills_graph.loaded"), do: [:jido_skill_graph, :loaded]
  defp telemetry_event("skills_graph.reloaded"), do: [:jido_skill_graph, :reloaded]
  defp telemetry_event("skills_graph.node_read"), do: [:jido_skill_graph, :node_read]
  defp telemetry_event(_event_name), do: [:jido_skill_graph, :event]
end
