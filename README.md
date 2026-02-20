# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Current Status

MCP functionality has been removed from this repository.

`jido_skill_graph` now focuses on:

- markdown skill discovery/parsing
- graph snapshot build/reload/runtime
- query/search APIs
- optional Jido runtime integration hooks

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
