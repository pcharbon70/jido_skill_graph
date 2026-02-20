# Migration: Legacy Loader to `jido_skill_graph`

This guide documents how to replace direct skill-file loading with
`jido_skill_graph`.

## Why Migrate

- move parsing/discovery logic into one maintained package
- get atomic snapshot reload semantics
- enable graph traversal/search APIs instead of ad hoc file scans

## Before (Legacy Pattern)

- application code discovers markdown files directly
- application code parses frontmatter and links
- application code owns in-memory caches and refresh logic

## After (Recommended Pattern)

1. Start graph runtime under your supervision tree.
2. Trigger reloads via `JidoSkillGraph.reload/2` (or watcher mode).
3. Read graph data through public query APIs or adapter helpers.

## Step-by-Step

1. Runtime wiring:
   - add `{JidoSkillGraph, [...]}` or `JidoSkillGraph.JidoAdapter.child_spec/1`.
2. Replace direct file reads:
   - use `list_nodes/2` for metadata
   - use `read_node_body/3` for lazy content reads
3. Replace bespoke link traversal:
   - use `out_links/3`, `in_links/3`, and `neighbors/3`.
4. Replace bespoke search:
   - use `search/3` (or configured search backend).

## JidoAI Migration Path

- use `JidoSkillGraph.JidoAIAdapter` wrappers to keep orchestration code simple
- keep selection policy in JidoAI
- keep graph internals in `jido_skill_graph`
