# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 8 Status

This phase establishes pluggable search backend behavior:

- `JidoSkillGraph.search/3` is available via facade and query layers
- `JidoSkillGraph.SearchBackend` defines the extension contract
- `JidoSkillGraph.SearchBackend.Basic` provides weighted substring search over id/title/tags/body

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
