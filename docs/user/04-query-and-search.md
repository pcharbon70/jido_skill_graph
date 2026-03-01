# 04 - Query and Search

Use the supervised runtime for repeated queries.

## Start Runtime and Load Graph

```elixir
root = Path.expand("examples/gardening_skills_app/skills")

{:ok, _pid} =
  Jido.Skillset.start_link(
    name: Demo.Graph,
    store: [name: Demo.Store],
    loader: [name: Demo.Loader, load_on_start: false, builder_opts: [root: root]]
  )

:ok = Jido.Skillset.reload(Demo.Loader)
graph_id = Jido.Skillset.list_graphs(store: Demo.Store) |> List.first()
```

## Common Query Calls

```elixir
{:ok, topology} = Jido.Skillset.topology(graph_id, store: Demo.Store)
{:ok, nodes} = Jido.Skillset.list_nodes(graph_id, store: Demo.Store, sort_by: :title)
{:ok, links} = Jido.Skillset.out_links(graph_id, "garden-basics", store: Demo.Store)
{:ok, neighbors} = Jido.Skillset.neighbors(graph_id, "garden-basics", store: Demo.Store, hops: 2)
{:ok, body} = Jido.Skillset.read_node_body(graph_id, "compost", store: Demo.Store, trim: true)
```

## Search

Default search backend is indexed search.

```elixir
{:ok, results} =
  Jido.Skillset.search(graph_id, "soil compost",
    store: Demo.Store,
    limit: 5,
    operator: :and,
    fuzzy: true
  )
```

To force legacy substring matching:

```elixir
Jido.Skillset.search(graph_id, "soil compost",
  store: Demo.Store,
  search_backend: Jido.Skillset.SearchBackend.Basic
)
```
