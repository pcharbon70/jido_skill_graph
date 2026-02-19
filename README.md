# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 6 Status

This phase establishes supervised runtime reload and snapshot swap behavior:

- `JidoSkillGraph.Store` publishes snapshots atomically through `:persistent_term`
- `JidoSkillGraph.Loader` performs versioned reloads and preserves active snapshot on build failure
- `JidoSkillGraph` supervisor wiring now propagates store/loader/watcher names and reload options

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
