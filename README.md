# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 12 Status

This phase adds explicit core telemetry contracts and documentation for runtime observability:

- `JidoSkillGraph.Loader` emits `[:jido_skill_graph, :loader, :reload]` with duration and status metadata
- `JidoSkillGraph.Store` emits `[:jido_skill_graph, :store, :snapshot_swap]` for successful and failed swaps
- `JidoSkillGraph.read_node_body/3` emits `[:jido_skill_graph, :query, :node_read]` for both success and failure
- telemetry contracts and measurements are documented in `docs/architecture/telemetry-events.md`

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
