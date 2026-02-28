# 03 - Build and Inspect a Graph

Use `Jido.Skillset.build/1` when you want to build a snapshot without starting supervised processes.

## One-Off Build

```elixir
{:ok, snapshot} =
  Jido.Skillset.build(
    root: "examples/gardening_skills_app/skills",
    graph_id: "home-gardening"
  )

IO.inspect(%{
  graph_id: snapshot.graph_id,
  node_count: map_size(snapshot.nodes),
  edge_count: length(snapshot.edges),
  warnings: snapshot.warnings,
  stats: snapshot.stats
})
```

Run this with:

```sh
mix run -e '{:ok, s} = Jido.Skillset.build(root: "examples/gardening_skills_app/skills", graph_id: "home-gardening"); IO.inspect(%{graph_id: s.graph_id, node_count: map_size(s.nodes), edge_count: length(s.edges), warnings: s.warnings})'
```

You can also paste the Elixir snippet into `iex -S mix`.

## Build Options You Will Use Most

- `root`: directory containing `graph.yml` and skill files
- `graph_id`: explicit graph id (otherwise inferred)
- `manifest_path`: explicit manifest file path
- `unresolved_link_policy`: how unresolved links are handled
