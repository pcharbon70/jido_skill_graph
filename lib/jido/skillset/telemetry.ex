defmodule Jido.Skillset.Telemetry do
  @moduledoc """
  Core telemetry event dispatcher for runtime and query operations.
  """

  @prefix [:jido_skillset]

  @type event :: [atom()]

  @spec execute(event(), map(), map()) :: :ok
  def execute(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@prefix ++ event, measurements, metadata)
  end

  @spec duration_measurements(integer()) :: map()
  def duration_measurements(duration_native)
      when is_integer(duration_native) and duration_native >= 0 do
    %{
      count: 1,
      duration_native: duration_native,
      duration_ms: System.convert_time_unit(duration_native, :native, :millisecond)
    }
  end
end
