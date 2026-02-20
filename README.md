# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 13 Status

This phase prepares MCP boundary extraction with a standalone-ready wrapper namespace:

- `JidoSkillGraphMCP`, `JidoSkillGraphMCP.Tools`, and `JidoSkillGraphMCP.Resources` now own MCP behavior
- existing `JidoSkillGraph.MCP*` modules are compatibility delegates to the new namespace
- tests verify both the new namespace and compatibility layer return equivalent behavior

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
