# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 9 Status

This phase establishes MCP-facing tool and resource modules:

- `JidoSkillGraph.MCP.Tools` exposes:
  - `skills_graph.list`
  - `skills_graph.topology`
  - `skills_graph.node_links`
  - `skills_graph.search`
- `JidoSkillGraph.MCP.Resources` supports `skill://<graph_id>/<node_id>` resource reads
- `JidoSkillGraph.MCP` provides a simple facade for tools/resources

## Development

Install toolchain and dependencies:

```sh
asdf install
mix deps.get
```

Run checks:

```sh
mix test
mix credo --strict
mix dialyzer
```
