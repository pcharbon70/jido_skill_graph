# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 11 Status

This phase moves snapshot reads onto ETS-backed indexes while preserving the existing public API:

- `JidoSkillGraph.Store` builds and publishes snapshot-local ETS indexes during atomic swaps
- `JidoSkillGraph.Snapshot` now carries `ets_nodes` and `ets_edges` handles with helper accessors
- `JidoSkillGraph.Query` resolves nodes/edges through snapshot helpers so read paths use ETS when available
- tests cover ETS index materialization and accessor behavior

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
