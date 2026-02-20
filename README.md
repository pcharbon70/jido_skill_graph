# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 10 Status

This phase introduces optional Jido runtime integration hooks without adding a hard Jido dependency:

- `JidoSkillGraph.EventPublisher` behavior defines a pluggable publish contract
- `JidoSkillGraph.Loader` emits:
  - `skills_graph.loaded`
  - `skills_graph.reloaded`
- `JidoSkillGraph.read_node_body/3` can emit `skills_graph.node_read`
- `JidoSkillGraph.JidoAdapter` provides optional integration helpers
- `JidoSkillGraph.JidoAdapter.SignalPublisher` emits telemetry and can bridge into `jido_signal` when present

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
