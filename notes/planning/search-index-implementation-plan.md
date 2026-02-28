# Search Improvement Plan (No External Database)

Date: 2026-02-27
Status: Proposed
Owner: jido_skill_graph maintainers

## 1. Goal

Improve search quality and latency without introducing an external database by
building and querying an in-memory index that is rebuilt during graph reload.

## 2. Scope

In scope:

- In-memory inverted index built at snapshot build time
- ETS-backed index access for fast concurrent reads
- New search backend with weighted ranking (BM25F-inspired)
- Faster excerpt generation without parsing files during query
- Optional typo tolerance through a trigram index

Out of scope:

- External storage engines (Postgres/Elastic/OpenSearch/etc.)
- Embeddings/vector DB integration
- Runtime orchestration or tool-routing policy changes

## 3. Current Baseline (What We Are Replacing)

Current behavior in `JidoSkillGraph.SearchBackend.Basic`:

- Scans all nodes on each query
- Reads/parses markdown body files during search when `:body` is included
- Uses simple weighted substring scoring

Primary bottlenecks:

- O(N) scan per query
- repeated file parsing in hot path

## 4. Target Architecture

- Build phase (`Builder.build/1`) produces:
  - graph snapshot (existing)
  - search index payload (new)
- Store phase (`Store.swap_snapshot/2`) publishes:
  - snapshot in `:persistent_term` (existing)
  - ETS search tables (new)
- Query phase (`Query.search/4`) uses:
  - pluggable backend (existing)
  - new indexed backend (new default after rollout)

## 5. Phased Implementation Plan

### Phase 0: Baseline Instrumentation and Guardrails

Objective:
Establish measurable baseline and safe rollout controls.

Changes:

- Add telemetry around search execution duration/result count in search path.
- Add backend toggle:
  - `search_backend: JidoSkillGraph.SearchBackend.Basic` (existing)
  - `search_backend: JidoSkillGraph.SearchBackend.Indexed` (new)
- Keep Basic backend as fallback during rollout.

Deliverables:

- Search telemetry contract documented in `docs/architecture/telemetry-events.md`
- Baseline benchmark script or test helper for representative query corpus

Acceptance criteria:

- Search telemetry emitted for every query call
- Existing test suite remains green

---

### Phase 1: Index Data Model and Snapshot Extensions

Objective:
Define index structures and include them in snapshot lifecycle.

Changes:

- Introduce new module(s):
  - `lib/jido_skill_graph/search_index.ex` (types + builder helpers)
  - `lib/jido_skill_graph/search_index/tokenizer.ex` (normalization/tokenization)
- Extend `JidoSkillGraph.Snapshot` with optional in-memory search artifacts:
  - index metadata (document count, avg field lengths, build version)
  - optional body cache metadata for excerpts
- Keep backward compatibility:
  - snapshot works even when index is absent

Data structures:

- Inverted index postings:
  - key: `{term, field}`
  - value: `{node_id, tf, positions_or_offsets}`
- Document stats:
  - per node field lengths (`id`, `title`, `tags`, `body`)
  - corpus totals and averages

Acceptance criteria:

- Snapshot can carry index metadata without breaking existing APIs
- Unit tests added for tokenization and normalization rules

---

### Phase 2: Build-Time Index Construction

Objective:
Build index once during reload/build path.

Changes:

- Update `JidoSkillGraph.Builder`:
  - tokenize indexed fields for each node
  - parse body once during build for indexing payload
  - compute document frequencies and field stats
- Optional optimization:
  - store compact cached body text or excerpt windows per node

Performance constraints:

- Build can be slower than query; target predictable reload cost
- Keep memory bounded by:
  - max token length
  - stop-word filtering
  - optional position tracking toggle

Acceptance criteria:

- Builder returns snapshot with deterministic index metadata
- Determinism test proves same input => same index checksum/stats
- Existing builder/query tests still pass

---

### Phase 3: Store-Level ETS Index Publishing

Objective:
Publish index into ETS for low-latency concurrent reads.

Changes:

- Extend `JidoSkillGraph.Store` to create and populate additional ETS table(s):
  - postings table
  - document stats table
  - optional trigram table placeholder (for later phase)
- Attach ETS references to snapshot similarly to existing node/edge tables.
- Preserve atomic semantics:
  - only swap `:persistent_term` after ETS index tables are fully built
  - cleanup previous index tables after successful swap

Failure handling:

- If index ETS creation/population fails:
  - do not publish partial snapshot
  - return error and keep current snapshot active

Acceptance criteria:

- Snapshot swap remains atomic with index tables included
- Concurrent read test during swap still passes
- Failure path test verifies active snapshot is unchanged

---

### Phase 4: New Indexed Search Backend

Objective:
Replace O(N) scan with postings-based retrieval and weighted ranking.

Changes:

- Add `lib/jido_skill_graph/search_backend/indexed.ex`
- Implement candidate generation:
  - union/intersection on postings for query terms
  - optional AND/OR mode (default OR with scoring penalties for partial matches)
- Implement ranking:
  - BM25F-inspired weighted score across fields:
    - `title` highest
    - `tags` high
    - `id` medium
    - `body` lower
  - tie-break deterministic by `id`
- Implement query options:
  - `fields`, `limit` (compat with current backend)
  - optional `operator: :and | :or`

Backward compatibility:

- Keep output schema aligned with `SearchBackend.result/0`

Acceptance criteria:

- Search results deterministic for same corpus/query/options
- Query latency improves materially vs baseline on medium corpus
- Regression tests validate compatibility with existing search API

---

### Phase 5: Excerpts and Body-Read Elimination in Hot Path

Objective:
Generate excerpts without reparsing markdown files at query time.

Changes:

- During build, store either:
  - normalized body text cache, or
  - token offsets/snippet windows
- Indexed backend excerpt generation reads from cache/index tables only.
- Ensure memory controls:
  - configurable max cached body bytes per node
  - fallback to nil excerpt if capped

Acceptance criteria:

- No `SkillFile.parse/1` calls inside indexed search execution path
- Excerpts still available for body hits in common cases
- Memory budget tests for capped cache behavior

---

### Phase 6 (Optional): Typo Tolerance via Trigram Index

Objective:
Improve recall for misspellings without external fuzzy engine.

Changes:

- Build trigram -> term dictionary index
- Query flow:
  - if exact term has low/no postings, expand with nearest trigram candidates
  - cap expansions per term to avoid recall explosion
- Add option:
  - `fuzzy: false | true` (default false initially)

Acceptance criteria:

- Misspelled queries recover relevant results in targeted tests
- Precision remains acceptable with conservative expansion thresholds

---

### Phase 7: Indexed Backend as Default

Objective:
Make indexed search the default runtime path while retaining explicit fallback.

Changes:

- Set `JidoSkillGraph.Query.search/4` default backend to
  `JidoSkillGraph.SearchBackend.Indexed`.
- Keep explicit backend override support so callers can still pass
  `search_backend: JidoSkillGraph.SearchBackend.Basic` when needed.
- Update telemetry expectations and regression tests for default-backend behavior.

Acceptance criteria:

- `JidoSkillGraph.search/3` uses indexed backend when `search_backend` is omitted.
- Existing override semantics remain backward compatible.
- Search telemetry backend metadata reflects indexed default path.

## 6. Testing Plan by Layer

Unit tests:

- Tokenizer normalization, stopwords, stemming policy (if adopted)
- Posting list build and merge correctness
- BM25F score calculation deterministic and monotonic with term frequency

Integration tests:

- Builder -> Store -> Query indexed path end-to-end
- Atomic swap behavior with index tables on success/failure
- Search parity tests vs Basic backend on core fixtures

Performance tests:

- Benchmark representative corpora:
  - small (10-50 nodes), medium (100-500), large (1000+ synthetic)
- Compare p50/p95 latency for baseline vs indexed
- Track memory growth across corpus sizes

## 7. Rollout Strategy

1. Ship Phases 0-3 behind explicit backend opt-in.
2. Ship Phase 4 and run parallel validation:
   - keep Basic as fallback in config.
3. Make indexed backend default after quality/perf thresholds are met.
4. Add Phase 5 optimizations.
5. Evaluate and optionally enable Phase 6 fuzzy mode.

## 8. Risks and Mitigations

Risk: Memory growth from postings/body cache.
Mitigation: configurable caps, stop-word filtering, optional position tracking.

Risk: Relevance regressions compared to simple substring behavior.
Mitigation: backend toggle + parity tests + staged rollout.

Risk: More complex swap failures due to extra ETS tables.
Mitigation: all-or-nothing publish semantics and failure-path tests.

Risk: Increased reload time.
Mitigation: measure build times; optimize tokenizer and index serialization; keep
query path fast as primary objective.

## 9. Definition of Done

- Indexed backend available and production-ready for default use
- No markdown file parsing in query hot path
- Atomic swap guarantees preserved with index tables
- Telemetry covers build/swap/query performance
- Documentation updated:
  - architecture
  - telemetry
  - runtime config examples
