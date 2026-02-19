# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 2 Status

This phase establishes the package bootstrap and architecture skeleton:

- supervised runtime entrypoint (`JidoSkillGraph.child_spec/1`)
- pure builder entrypoint (`JidoSkillGraph.Builder.build/1`)
- core module layout for manifest, builder, extraction, store, loader, watcher, and search backend behavior

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
