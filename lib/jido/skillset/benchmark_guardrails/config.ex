defmodule Jido.Skillset.BenchmarkGuardrails.Config do
  @moduledoc """
  Loader for JSON-based benchmark guardrail configuration files.
  """

  @allowed_keys ~w(min_speedup_p50 min_speedup_p95 max_memory_delta_mb enforce_profiles)
  @profile_names MapSet.new(~w(fixture small medium large all))

  @type reason ::
          {:file_read_failed, term()}
          | {:decode_failed, term()}
          | :expected_object
          | {:invalid_value, String.t(), String.t()}

  @spec load(String.t()) :: {:ok, map()} | {:error, reason()}
  def load(path) when is_binary(path) and path != "" do
    with {:ok, contents} <- read_file(path),
         {:ok, decoded} <- decode_json(contents),
         {:ok, config} <- ensure_object(decoded) do
      config
      |> Map.take(@allowed_keys)
      |> validate()
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

  defp validate(config) do
    config
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case validate_entry(key, value) do
        {:ok, normalized} ->
          {:cont, {:ok, Map.put(acc, key, normalized)}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_value, key, reason}}}
      end
    end)
  end

  defp validate_entry("min_speedup_p50", value), do: validate_positive_number(value)
  defp validate_entry("min_speedup_p95", value), do: validate_positive_number(value)
  defp validate_entry("max_memory_delta_mb", value), do: validate_non_negative_number(value)
  defp validate_entry("enforce_profiles", value), do: validate_profiles(value)
  defp validate_entry(_key, value), do: {:ok, value}

  defp validate_positive_number(value) when is_number(value) and value > 0, do: {:ok, value}
  defp validate_positive_number(value) when is_number(value), do: {:error, "must be > 0"}
  defp validate_positive_number(_value), do: {:error, "must be a number"}

  defp validate_non_negative_number(value) when is_number(value) and value >= 0, do: {:ok, value}
  defp validate_non_negative_number(value) when is_number(value), do: {:error, "must be >= 0"}
  defp validate_non_negative_number(_value), do: {:error, "must be a number"}

  defp validate_profiles(values) when is_list(values) do
    with {:ok, normalized} <- normalize_profiles(values) do
      {:ok, normalized |> Enum.reverse() |> Enum.uniq()}
    end
  end

  defp validate_profiles(_values), do: {:error, "must be an array of profile names"}

  defp normalize_profiles(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_profile(value) do
        {:ok, profile} -> {:cont, {:ok, [profile | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_profile(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    cond do
      normalized == "" ->
        {:error, "contains an empty profile name"}

      MapSet.member?(@profile_names, normalized) ->
        {:ok, normalized}

      true ->
        {:error, "contains unknown profile '#{normalized}'"}
    end
  end

  defp normalize_profile(_value), do: {:error, "contains a non-string profile name"}
end
