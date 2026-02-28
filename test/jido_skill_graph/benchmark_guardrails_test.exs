defmodule JidoSkillGraph.BenchmarkGuardrailsTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.BenchmarkGuardrails

  test "configured?/1 returns false when no thresholds are provided" do
    refute BenchmarkGuardrails.configured?(opts())
  end

  test "configured?/1 returns true when any threshold is provided" do
    assert BenchmarkGuardrails.configured?(opts(min_speedup_p50: 3.0))
    assert BenchmarkGuardrails.configured?(opts(min_speedup_p95: 2.0))
    assert BenchmarkGuardrails.configured?(opts(max_memory_delta_mb: 80.0))
  end

  test "enforced_profiles/1 defaults to non-fixture suite profiles in all mode" do
    assert BenchmarkGuardrails.enforced_profiles(opts(profile_mode: :all)) == [
             :small,
             :medium,
             :large
           ]
  end

  test "enforced_profiles/1 uses explicit enforce_profiles when provided" do
    assert BenchmarkGuardrails.enforced_profiles(
             opts(profile_mode: :all, enforce_profiles: [:fixture, :small])
           ) == [:fixture, :small]
  end

  test "evaluate/2 returns no failures when guardrails are not configured" do
    reports = [report(:small, 10.0, 2.0, 2.2, 8.0, 8.8)]
    assert BenchmarkGuardrails.evaluate(opts(), reports) == []
  end

  test "evaluate/2 reports missing profile data for enforced profiles" do
    failures =
      BenchmarkGuardrails.evaluate(
        opts(min_speedup_p50: 3.0, enforce_profiles: [:small, :large]),
        [report(:small, 10.0, 2.0, 2.0, 8.0, 8.0)]
      )

    assert length(failures) == 1
    assert Enum.any?(failures, &String.contains?(&1, "profile=large missing"))
  end

  test "evaluate/2 reports speedup threshold failures" do
    failures =
      BenchmarkGuardrails.evaluate(
        opts(profile_mode: :small, min_speedup_p50: 6.0, min_speedup_p95: 5.0),
        [report(:small, 10.0, 10.0, 12.0, 50.0, 55.0)]
      )

    assert length(failures) == 2
    assert Enum.any?(failures, &String.contains?(&1, "speedup_p50=5.0x"))
    assert Enum.any?(failures, &String.contains?(&1, "speedup_p95=4.583x"))
  end

  test "evaluate/2 reports memory threshold failures" do
    failures =
      BenchmarkGuardrails.evaluate(
        opts(profile_mode: :large, max_memory_delta_mb: 40.0),
        [report(:large, 55.5, 12.0, 13.0, 220.0, 240.0)]
      )

    assert length(failures) == 1
    assert Enum.any?(failures, &String.contains?(&1, "memory_delta_mb=55.5"))
    assert Enum.any?(failures, &String.contains?(&1, "max_memory_delta_mb=40.0"))
  end

  test "evaluate/2 reports missing backend metrics when speedup cannot be computed" do
    failures =
      BenchmarkGuardrails.evaluate(
        opts(profile_mode: :small, min_speedup_p50: 3.0),
        [report(:small, 10.0, 2.0, 2.2, nil, nil)]
      )

    assert length(failures) == 1

    assert Enum.any?(
             failures,
             &String.contains?(
               &1,
               "requires both indexed/basic results to evaluate min_speedup_p50"
             )
           )
  end

  test "status/2 reflects configured, pass, and fail states" do
    assert BenchmarkGuardrails.status(opts(), []) == :not_configured
    assert BenchmarkGuardrails.status(opts(min_speedup_p50: 3.0), []) == :pass
    assert BenchmarkGuardrails.status(opts(min_speedup_p50: 3.0), ["failure"]) == :fail
  end

  defp opts(overrides \\ []) do
    Map.merge(
      %{
        profile_mode: :all,
        enforce_profiles: nil,
        min_speedup_p50: nil,
        min_speedup_p95: nil,
        max_memory_delta_mb: nil
      },
      Enum.into(overrides, %{})
    )
  end

  defp report(profile, memory_delta_mb, indexed_p50, indexed_p95, basic_p50, basic_p95) do
    %{
      profile: profile,
      corpus: %{memory_delta_bytes: trunc(memory_delta_mb * 1_048_576)},
      results:
        %{}
        |> maybe_put_backend(:indexed, indexed_p50, indexed_p95)
        |> maybe_put_backend(:basic, basic_p50, basic_p95)
    }
  end

  defp maybe_put_backend(results, _key, p50, p95) when not is_number(p50) or not is_number(p95) do
    results
  end

  defp maybe_put_backend(results, key, p50, p95) do
    Map.put(results, key, %{overall: %{p50_ms: p50, p95_ms: p95}})
  end
end
