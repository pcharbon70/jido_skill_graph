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
