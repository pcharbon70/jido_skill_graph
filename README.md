# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 5 Status

This phase establishes the pure-mode graph builder behavior:

- `JidoSkillGraph.Builder` now materializes a directed `Graph.t` topology
- `JidoSkillGraph.Topology` builds deterministic graph topology from normalized nodes/edges
- snapshot stats include topology counts and a reproducible snapshot checksum

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
