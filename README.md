# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Current Status

`jido_skill_graph` focuses on:

- markdown skill discovery/parsing
- graph snapshot build/reload/runtime
- query/search APIs
- optional Jido runtime integration hooks

## Compatibility

- Elixir `>= 1.17`
- Erlang/OTP `>= 27`

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

Run a local search benchmark (indexed default):

```sh
mix run scripts/search_benchmark.exs --iterations 100
```

Compare indexed vs basic in one run (includes p50/p95 speedup output):

```sh
mix run scripts/search_benchmark.exs --backend both --iterations 200 --warmup-iterations 20
```

Run only the legacy basic backend:

```sh
mix run scripts/search_benchmark.exs --backend basic --iterations 100
```

## Local Development Configuration Example

Supervised runtime with explicit store/loader names:

```elixir
children = [
  {JidoSkillGraph,
   name: MyApp.SkillGraph,
   store: [name: MyApp.SkillGraph.Store],
   loader: [
     name: MyApp.SkillGraph.Loader,
     load_on_start: true,
     builder_opts: [
       root: "notes/skills",
       graph_id: "local-dev"
     ]
   ],
   watch?: false}
]
```

## Search Runtime Examples

Default search uses the indexed backend:

```elixir
JidoSkillGraph.search("local-dev", "alpha references", store: MyApp.SkillGraph.Store)
```

Force legacy substring behavior explicitly:

```elixir
JidoSkillGraph.search("local-dev", "alpha references",
  store: MyApp.SkillGraph.Store,
  search_backend: JidoSkillGraph.SearchBackend.Basic
)
```

Enable typo tolerance in indexed mode:

```elixir
JidoSkillGraph.search("local-dev", "alpah references",
  store: MyApp.SkillGraph.Store,
  operator: :and,
  fuzzy: true,
  fuzzy_max_expansions: 4,
  fuzzy_min_similarity: 0.2
)
```
