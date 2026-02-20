# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 15 Status

This phase adds JidoAI-consumer integration helpers and migration guidance:

- `JidoSkillGraph.JidoAIAdapter` exposes orchestration-facing wrappers over public graph APIs
- tests cover candidate listing, lazy reads, related-skill traversal, and search delegation
- migration notes now document replacing direct legacy loaders with `jido_skill_graph`

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
