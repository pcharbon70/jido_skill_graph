defmodule Jido.Skillset.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_skillset,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Skillset.Application, []}
    ]
  end

  defp deps do
    [
      {:libgraph, "~> 0.16"},
      {:yaml_elixir, "~> 2.11"},
      {:telemetry, "~> 1.2"},
      {:jido_signal, "~> 1.2", optional: true},
      {:file_system, "~> 1.1", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
