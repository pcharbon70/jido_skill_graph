# 06 - Troubleshooting

## Common Errors

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| `{:error, :graph_not_loaded}` | No snapshot loaded in store yet | Start runtime and run `Jido.Skillset.reload/1` |
| `{:error, {:unknown_graph, graph_id}}` | Wrong graph ID passed to query | Check `Jido.Skillset.list_graphs/1` |
| `{:error, {:unknown_node, node_id}}` | Node ID does not exist | Use `list_nodes/2` to inspect valid IDs |
| `{:error, :body_unavailable}` | Node has no readable body reference | Verify skill file is present and parseable |
| `{:error, {:invalid_relation_filter, value}}` | Invalid `rel` option in link queries | Use supported relations: `related`, `prereq`, `extends`, `contains`, `references` |

## Build Failures

- Confirm frontmatter is valid YAML.
- Confirm each skill file is valid markdown and has expected frontmatter keys.
- Confirm `root` points to the graph folder containing `graph.yml`.

## Search Quality or Performance Issues

- Keep default indexed backend unless you need legacy substring behavior.
- Tune search options (`operator`, `fuzzy`, `fuzzy_max_expansions`, `fuzzy_min_similarity`).
- Run benchmark scripts to compare profiles and backends:

```sh
mix run scripts/search_benchmark.exs --profile all --backend both --iterations 20 --warmup-iterations 5
```

## More Examples

- `examples/gardening_skills_app/run.exs`
- `examples/elixir_programming_skills/run.exs`
