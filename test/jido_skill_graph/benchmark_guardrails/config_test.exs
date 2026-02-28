defmodule JidoSkillGraph.BenchmarkGuardrails.ConfigTest do
  use ExUnit.Case, async: true

  alias JidoSkillGraph.BenchmarkGuardrails.Config

  test "load/1 returns configured guardrail keys from JSON object" do
    path =
      write_temp_file("""
      {
        "enforce_profiles": ["small", "medium", "large"],
        "min_speedup_p50": 3.0,
        "min_speedup_p95": 2.5,
        "max_memory_delta_mb": 120,
        "ignored_key": true
      }
      """)

    assert {:ok, config} = Config.load(path)

    assert config == %{
             "enforce_profiles" => ["small", "medium", "large"],
             "min_speedup_p50" => 3.0,
             "min_speedup_p95" => 2.5,
             "max_memory_delta_mb" => 120
           }
  end

  test "load/1 returns decode_failed for malformed json" do
    path = write_temp_file("{invalid")

    assert {:error, {:decode_failed, _reason}} = Config.load(path)
  end

  test "load/1 returns expected_object when root JSON value is not an object" do
    path = write_temp_file("[1,2,3]")

    assert {:error, :expected_object} = Config.load(path)
  end

  test "load/1 returns file_read_failed when file does not exist" do
    missing_path =
      Path.join(
        System.tmp_dir!(),
        "jsg_guardrail_missing_#{System.unique_integer([:positive])}.json"
      )

    assert {:error, {:file_read_failed, :enoent}} = Config.load(missing_path)
  end

  defp write_temp_file(contents) do
    path =
      Path.join(System.tmp_dir!(), "jsg_guardrail_#{System.unique_integer([:positive])}.json")

    :ok = File.write(path, contents)
    on_exit(fn -> _ = File.rm(path) end)
    path
  end
end
