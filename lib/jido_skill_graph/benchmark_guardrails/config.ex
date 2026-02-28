defmodule JidoSkillGraph.BenchmarkGuardrails.Config do
  @moduledoc """
  Loader for JSON-based benchmark guardrail configuration files.
  """

  @allowed_keys ~w(min_speedup_p50 min_speedup_p95 max_memory_delta_mb enforce_profiles)

  @type reason ::
          {:file_read_failed, term()}
          | {:decode_failed, term()}
          | :expected_object

  @spec load(String.t()) :: {:ok, map()} | {:error, reason()}
  def load(path) when is_binary(path) and path != "" do
    with {:ok, contents} <- read_file(path),
         {:ok, decoded} <- decode_json(contents),
         {:ok, config} <- ensure_object(decoded) do
      {:ok, Map.take(config, @allowed_keys)}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:file_read_failed, reason}}
    end
  end

  defp decode_json(contents) do
    case Jason.decode(contents) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:decode_failed, reason}}
    end
  end

  defp ensure_object(config) when is_map(config), do: {:ok, config}
  defp ensure_object(_config), do: {:error, :expected_object}
end
