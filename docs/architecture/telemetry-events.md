# Telemetry Events

This document defines the core telemetry contract emitted by `jido_skillset`.

All events use the `[:jido_skillset, ...]` prefix.

## Loader Reload

- Event: `[:jido_skillset, :loader, :reload]`
- Emitted when `Jido.Skillset.Loader` completes a reload attempt (success or failure).

Measurements:

- `count` - always `1`
- `duration_native` - elapsed time in native units
- `duration_ms` - elapsed time in milliseconds

Metadata (success):

- `status` - `:ok`
- `graph_id` - loaded graph id
- `version` - committed snapshot version
- `warning_count` - count of snapshot warnings
- `store` - configured store name (inspected)

Metadata (failure):

- `status` - `:error`
- `reason` - inspected error reason
- `store` - configured store name (inspected)

## Store Snapshot Swap

- Event: `[:jido_skillset, :store, :snapshot_swap]`
- Emitted when `Jido.Skillset.Store` processes a snapshot swap attempt.

Measurements:

- `count` - always `1`
- `duration_native` - elapsed time in native units
- `duration_ms` - elapsed time in milliseconds

Metadata (success):

- `status` - `:ok`
- `graph_id` - committed graph id
- `version` - committed snapshot version
- `node_count` - number of nodes in committed snapshot
- `edge_count` - number of edges in committed snapshot
- `search_term_count` - number of indexed `{term, field}` posting keys

Metadata (failure):

- `status` - `:error`
- `reason` - inspected error reason

## Query Node Read

- Event: `[:jido_skillset, :query, :node_read]`
- Emitted when `Jido.Skillset.read_node_body/3` is called and completes (success or failure).

Measurements:

- `count` - always `1`
- `bytes` - body payload size in bytes, `0` when read fails

Metadata:

- `status` - `:ok` or `:error`
- `graph_id` - requested graph id
- `node_id` - requested node id
- `version` - active snapshot version
- `with_frontmatter` - whether `with_frontmatter: true` was requested
- `trim` - whether `trim: true` was requested

## Query Search

- Event: `[:jido_skillset, :query, :search]`
- Emitted when `Jido.Skillset.search/3` completes (success or failure).

Measurements:

- `count` - always `1`
- `duration_native` - elapsed time in native units
- `duration_ms` - elapsed time in milliseconds
- `result_count` - number of returned results (`0` on error)
- `query_bytes` - query string byte size (`0` when query is non-binary)

Metadata:

- `status` - `:ok` or `:error`
- `graph_id` - requested graph id
- `backend` - configured backend module (inspected). Defaults to
  `Jido.Skillset.SearchBackend.Indexed` when not explicitly provided.
- `fields` - requested fields option or `:default`
- `limit` - requested limit option (defaults to `20`)
- `operator` - requested operator option (`:or` by default)
- `fuzzy` - requested fuzzy toggle (`false` by default)
- `fuzzy_max_expansions` - requested fuzzy candidate cap (`3` by default)
- `fuzzy_min_similarity` - requested trigram similarity threshold (`0.2` by default)
