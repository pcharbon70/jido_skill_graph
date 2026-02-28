# Skill Graph Architecture (Revised Scope)

This document captures the scoped architecture for `jido_skillset` as a
standalone graph library.

## 1. Package Boundaries

`jido_skillset` owns:

- discovery of `SKILL.md` and `skill.md` files
- optional manifest parsing (`graph.yml`)
- frontmatter parsing and markdown link extraction
- directed graph build (cycles allowed)
- snapshot storage and reload semantics
- graph query and search APIs

`jido_skillset` does not own:

- skill authoring workflows
- runtime orchestration policy
- assistant-specific UX, tool routing, or registry behavior
- MCP server/tool/resource surfaces

## 2. Operating Modes

Mode A: supervised runtime

- expose `child_spec/1`
- manage `Store`, `Loader`, and optional `Watcher`
- support atomic snapshot swaps for reload

Mode B: pure library

- expose `Builder.build/1`
- return immutable snapshot structs for tests/tooling

## 3. In-Memory Model

- use `libgraph` for directed topology
- use ETS tables for concurrent node/edge payload access
- keep graph topology and payload storage separated

Core structs:

- `Jido.Skillset.Node`
- `Jido.Skillset.Edge`
- `Jido.Skillset.Snapshot`

## 4. File Format Compatibility

- YAML frontmatter (optional)
- markdown body
- typed links from frontmatter
- wiki links (`[[node]]`)
- optional typed wiki-link conventions (`[[prereq:node]]`, `[[extends:node]]`)

## 5. Public API Surface

- `list_graphs/0`
- `topology/2`
- `list_nodes/2`
- `get_node_meta/2`
- `read_node_body/3`
- `out_links/3`
- `in_links/3`
- `neighbors/3`
- `search/3`

## 6. Integration Direction

- runtime integration should happen through adapters that call public APIs
- adapter logic must stay outside core graph internals
- core package must remain dependency-light and runtime-agnostic
