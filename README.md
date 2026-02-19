# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 7 Status

This phase establishes the public query API on top of loaded snapshots:

- `list_graphs/1`, `topology/2`, `list_nodes/2`, `get_node_meta/3`, `read_node_body/3`
- link traversal APIs: `out_links/3`, `in_links/3`, `neighbors/3`
- `JidoSkillGraph.Query` encapsulates graph/node/link query logic and filtering

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
