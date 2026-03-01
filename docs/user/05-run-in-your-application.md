# 05 - Run in Your Application

Use `Jido.Skillset` as a supervised child in your app.

## Child Spec

```elixir
children = [
  {Jido.Skillset,
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

## Operational Tips

- Use explicit `store` and `loader` names so multiple graphs can run in one VM.
- Use `Jido.Skillset.reload/2` for controlled refreshes.
- Enable `watch?: true` only when you need filesystem-triggered reloads.
- Read loader runtime state with `Jido.Skillset.Loader.status/1`.

## Events and Telemetry

- Reload events are emitted as `skills_graph.loaded` and `skills_graph.reloaded`.
- Node body reads can publish `skills_graph.node_read` through an event publisher module.
- Query and loader operations emit telemetry through `Jido.Skillset.Telemetry`.
