defmodule Jido.Skillset.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/jido_skillset"

  def project do
    [
      app: :jido_skillset,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      name: "Jido.Skillset",
      description: "Standalone markdown skill graph library with runtime query and search APIs.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
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
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Home"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "Apache 2.0 License"},
        {"docs/user/01-getting-started.md", title: "01 - Getting Started"},
        {"docs/user/02-author-skill-files.md", title: "02 - Author Skill Files"},
        {"docs/user/03-build-and-inspect-a-graph.md", title: "03 - Build and Inspect a Graph"},
        {"docs/user/04-query-and-search.md", title: "04 - Query and Search"},
        {"docs/user/05-run-in-your-application.md", title: "05 - Run in Your Application"},
        {"docs/user/06-troubleshooting.md", title: "06 - Troubleshooting"},
        {"docs/architecture/package-ownership.md", title: "Package Ownership"},
        {"docs/architecture/telemetry-events.md", title: "Telemetry Events"},
        {"docs/releases/versioning-policy.md", title: "Versioning Policy"},
        {"docs/releases/support-policy.md", title: "Support Policy"},
        {"docs/releases/v0.1-acceptance-criteria.md", title: "v0.1 Acceptance Criteria"},
        {"docs/rfcs/0001-standalone-skill-graph-architecture.md",
         title: "RFC 0001 - Standalone Skill Graph Architecture"}
      ],
      groups_for_extras: [
        Guides: [
          "docs/user/01-getting-started.md",
          "docs/user/02-author-skill-files.md",
          "docs/user/03-build-and-inspect-a-graph.md",
          "docs/user/04-query-and-search.md",
          "docs/user/05-run-in-your-application.md",
          "docs/user/06-troubleshooting.md"
        ],
        Architecture: [
          "docs/architecture/package-ownership.md",
          "docs/architecture/telemetry-events.md",
          "docs/rfcs/0001-standalone-skill-graph-architecture.md"
        ],
        Releases: [
          "CHANGELOG.md",
          "docs/releases/versioning-policy.md",
          "docs/releases/support-policy.md",
          "docs/releases/v0.1-acceptance-criteria.md"
        ],
        Project: [
          "LICENSE"
        ]
      ]
    ]
  end
end
