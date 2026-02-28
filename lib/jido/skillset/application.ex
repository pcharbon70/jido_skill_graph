defmodule Jido.Skillset.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido.Skillset, []}
    ]

    opts = [strategy: :one_for_one, name: Jido.Skillset.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
