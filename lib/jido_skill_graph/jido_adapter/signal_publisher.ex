defmodule JidoSkillGraph.JidoAdapter.SignalPublisher do
  @moduledoc """
  Event publisher that prefers `jido_signal` when present and always emits telemetry.
  """

  @behaviour JidoSkillGraph.EventPublisher

  @impl true
  def publish(event_name, payload, opts) do
    metadata = Map.merge(payload, Map.new(Keyword.get(opts, :metadata, [])))

    _ = maybe_emit_jido_signal(event_name, metadata)
    _ = emit_telemetry(event_name, metadata)

    :ok
  end

  defp maybe_emit_jido_signal(event_name, metadata) do
    candidates = [
      {Jido.Signal, :emit, [event_name, metadata]},
      {Jido.Signal, :publish, [event_name, metadata]},
      {JidoSignal, :emit, [event_name, metadata]},
      {JidoSignal, :publish, [event_name, metadata]}
    ]

    Enum.find_value(candidates, :ok, fn {module, function, args} ->
      if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
        apply(module, function, args)
      else
        false
      end
    end)
  end

  defp emit_telemetry(event_name, metadata) do
    :telemetry.execute(telemetry_event(event_name), %{count: 1}, metadata)
  end

  defp telemetry_event("skills_graph.loaded"), do: [:jido_skill_graph, :loaded]
  defp telemetry_event("skills_graph.reloaded"), do: [:jido_skill_graph, :reloaded]
  defp telemetry_event("skills_graph.node_read"), do: [:jido_skill_graph, :node_read]
  defp telemetry_event(_event_name), do: [:jido_skill_graph, :event]
end
