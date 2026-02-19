# Package Ownership Map

This document is the source of truth for ownership boundaries across the skill graph architecture.

## Core: `jido_skill_graph`

- Skill and manifest discovery
- Frontmatter and markdown parsing
- Link extraction and normalization
- Directed graph build and traversal APIs
- Snapshot state model and reload mechanics
- Search backend behavior and baseline implementation

## MCP Wrapper: `jido_skill_graph_mcp`

- MCP server setup and lifecycle
- Tool definitions and handlers
  - `skills_graph.list`
  - `skills_graph.topology`
  - `skills_graph.node_links`
  - `skills_graph.search`
- Resource routing
  - `skill://<graph_id>/<node_id>`

## Jido Adapter

- `child_spec/1` composition into Jido supervision trees
- Jido signal emission for load/reload/read events
- Runtime-specific configuration translation

## JidoAI Adapter

- Skill selection and orchestration logic
- Querying graph service as backend for skills retrieval
- Backward-compatible migration path from legacy loaders

## Explicit Ownership Rules

- Core package must not depend on Jido, JidoAI, or MCP libraries.
- MCP package may depend on core package, never the reverse.
- Adapters may depend on core package; core cannot depend on adapters.
- If a module needs both graph internals and transport/runtime internals, split it.
