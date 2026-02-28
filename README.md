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

Run synthetic corpus profiles to validate scaling and memory deltas:

```sh
mix run scripts/search_benchmark.exs --profile small --backend both --iterations 100
mix run scripts/search_benchmark.exs --profile medium --backend both --iterations 50
mix run scripts/search_benchmark.exs --profile large --backend both --iterations 20
```

Run all profiles in one pass and write a JSON report:

```sh
mix run scripts/search_benchmark.exs --profile all --backend both --iterations 20 --warmup-iterations 5 --output tmp/search_benchmark_report.json
```

Fail CI on perf regression with guardrails:

```sh
mix run scripts/search_benchmark.exs --profile all --backend both --iterations 10 --warmup-iterations 2 --min-speedup-p50 5.0 --min-speedup-p95 4.0 --max-memory-delta-mb 80 --output tmp/search_benchmark_guardrail.json
```

Or load guardrail thresholds from a tracked JSON config:

```sh
mix run scripts/search_benchmark.exs --profile all --backend both --iterations 10 --warmup-iterations 2 --guardrail-config scripts/search_benchmark_guardrails.ci.json --output tmp/search_benchmark_guardrail.json
```

The repository also includes an automated benchmark guardrail workflow:

- workflow: `.github/workflows/benchmark-guardrails.yml`
- triggers: pull requests, pushes to `main`, and manual dispatch
- config: `scripts/search_benchmark_guardrails.ci.json`
- artifact: `search-benchmark-report` (`tmp/search_benchmark_ci_report.json`)

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
