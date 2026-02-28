defmodule Jido.Skillset.EventPublisher.Noop do
  @moduledoc """
  No-op event publisher used by default in standalone mode.
  """

  @behaviour Jido.Skillset.EventPublisher

  @impl true
  def publish(_event_name, _payload, _opts), do: :ok
end
