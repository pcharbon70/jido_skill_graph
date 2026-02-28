defmodule JidoSkillGraph.BenchmarkGuardrails do
  @moduledoc """
  Benchmark guardrail evaluation shared by local scripts and CI workflows.
  """

  @type profile :: atom()
  @type report :: map()
  @type options :: map()

  @spec configured?(options()) :: boolean()
  def configured?(opts) when is_map(opts) do
    not is_nil(Map.get(opts, :min_speedup_p50)) or
      not is_nil(Map.get(opts, :min_speedup_p95)) or
      not is_nil(Map.get(opts, :max_memory_delta_mb))
  end

  @spec enforced_profiles(options()) :: [profile()]
  def enforced_profiles(%{enforce_profiles: profiles}) when is_list(profiles), do: profiles
  def enforced_profiles(%{profile_mode: :all}), do: [:small, :medium, :large]
  def enforced_profiles(%{profile_mode: profile}) when is_atom(profile), do: [profile]
  def enforced_profiles(_opts), do: []

  @spec evaluate(options(), [report()]) :: [String.t()]
  def evaluate(opts, reports) when is_map(opts) and is_list(reports) do
    if configured?(opts) do
      do_evaluate(enforced_profiles(opts), opts, reports)
    else
      []
    end
  end

  @spec status(options(), [String.t()]) :: :pass | :fail | :not_configured
  def status(opts, failures) when is_map(opts) and is_list(failures) do
    if configured?(opts) do
      if failures == [], do: :pass, else: :fail
    else
      :not_configured
    end
  end

  defp evaluate_profile_guardrails(profile, opts, report) do
    []
    |> maybe_add_memory_guardrail_failure(profile, opts, report)
    |> maybe_add_speedup_guardrail_failure(profile, :p50, opts, report)
    |> maybe_add_speedup_guardrail_failure(profile, :p95, opts, report)
  end

  defp do_evaluate(profiles, opts, reports) do
    Enum.flat_map(profiles, &evaluate_profile(&1, opts, reports))
  end

  defp evaluate_profile(profile, opts, reports) do
    case Enum.find(reports, &(&1.profile == profile)) do
      nil -> ["profile=#{profile} missing from benchmark report set"]
      report -> evaluate_profile_guardrails(profile, opts, report)
    end
  end

  defp maybe_add_memory_guardrail_failure(
         failures,
         _profile,
         %{max_memory_delta_mb: nil},
         _report
       ),
       do: failures

  defp maybe_add_memory_guardrail_failure(
         failures,
         profile,
         %{max_memory_delta_mb: threshold_mb},
         report
       ) do
    case memory_delta_mb(report) do
      value when is_number(value) and value <= threshold_mb ->
        failures

      value when is_number(value) ->
        failures ++
          [
            "profile=#{profile} memory_delta_mb=#{Float.round(value, 3)} exceeds max_memory_delta_mb=#{Float.round(threshold_mb, 3)}"
          ]

      _missing ->
        failures ++
          [
            "profile=#{profile} requires memory_delta_mb to evaluate max_memory_delta_mb"
          ]
    end
  end

  defp maybe_add_speedup_guardrail_failure(failures, profile, metric, opts, report) do
    threshold = speedup_threshold(opts, metric)

    if is_nil(threshold) do
      failures
    else
      speedup = overall_speedup(report, metric)

      cond do
        is_nil(speedup) ->
          failures ++
            [
              "profile=#{profile} requires both indexed/basic results to evaluate min_speedup_#{metric}"
            ]

        speedup >= threshold ->
          failures

        true ->
          failures ++
            [
              "profile=#{profile} speedup_#{metric}=#{Float.round(speedup, 3)}x below min_speedup_#{metric}=#{Float.round(threshold, 3)}x"
            ]
      end
    end
  end

  defp speedup_threshold(opts, :p50), do: Map.get(opts, :min_speedup_p50)
  defp speedup_threshold(opts, :p95), do: Map.get(opts, :min_speedup_p95)

  defp overall_speedup(report, metric) do
    indexed =
      get_in(report, [:results, :indexed, :overall, speedup_field(metric)])

    basic =
      get_in(report, [:results, :basic, :overall, speedup_field(metric)])

    if is_number(indexed) and indexed > 0 and is_number(basic) do
      basic / indexed
    else
      nil
    end
  end

  defp speedup_field(:p50), do: :p50_ms
  defp speedup_field(:p95), do: :p95_ms

  defp memory_delta_mb(report) do
    case get_in(report, [:corpus, :memory_delta_bytes]) do
      value when is_number(value) -> value / 1_048_576
      _ -> nil
    end
  end
end
