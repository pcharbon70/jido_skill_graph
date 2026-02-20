defmodule JidoSkillGraph.EventPublisher do
  @moduledoc """
  Behavior and dispatcher for optional runtime integration event publishing.
  """

  @callback publish(event_name :: String.t(), payload :: map(), opts :: keyword()) ::
              :ok | {:error, term()}

  @spec publish(module(), String.t(), map(), keyword()) :: :ok | {:error, term()}
  def publish(module, event_name, payload, opts)
      when is_atom(module) and is_binary(event_name) and is_map(payload) and is_list(opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, :publish, 3) do
      module.publish(event_name, payload, opts)
    else
      {:error, {:invalid_event_publisher, module}}
    end
  rescue
    error -> {:error, {:event_publisher_failed, error}}
  end
end
