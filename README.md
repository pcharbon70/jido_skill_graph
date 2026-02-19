# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 3 Status

This phase establishes strict contracts for core graph models:

- `JidoSkillGraph.Node` for identity and metadata
- `JidoSkillGraph.Edge` for typed relation taxonomy
- `JidoSkillGraph.Snapshot` for model validation and unresolved-link policy handling

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
