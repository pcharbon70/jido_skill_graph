# Search Improvement Plan (No External Database)

Date: 2026-02-27
Status: Proposed
Owner: jido_skillset maintainers

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

Current behavior in `Jido.Skillset.SearchBackend.Basic`:

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
  - `search_backend: Jido.Skillset.SearchBackend.Basic` (existing)
  - `search_backend: Jido.Skillset.SearchBackend.Indexed` (new)
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
  - `lib/jido_skillset/search_index.ex` (types + builder helpers)
  - `lib/jido_skillset/search_index/tokenizer.ex` (normalization/tokenization)
- Extend `Jido.Skillset.Snapshot` with optional in-memory search artifacts:
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

- Update `Jido.Skillset.Builder`:
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

- Extend `Jido.Skillset.Store` to create and populate additional ETS table(s):
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

- Add `lib/jido_skillset/search_backend/indexed.ex`
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

- Set `Jido.Skillset.Query.search/4` default backend to
  `Jido.Skillset.SearchBackend.Indexed`.
- Keep explicit backend override support so callers can still pass
  `search_backend: Jido.Skillset.SearchBackend.Basic` when needed.
- Update telemetry expectations and regression tests for default-backend behavior.

Acceptance criteria:

- `Jido.Skillset.search/3` uses indexed backend when `search_backend` is omitted.
- Existing override semantics remain backward compatible.
- Search telemetry backend metadata reflects indexed default path.

---

### Phase 8: Search Telemetry and Runtime Config Polish

Objective:
Improve observability and operational guidance for indexed-default search.

Changes:

- Extend query search telemetry metadata with:
  - `operator`
  - `fuzzy`
  - `fuzzy_max_expansions`
  - `fuzzy_min_similarity`
- Update telemetry documentation to include new metadata keys and indexed default.
- Add runtime configuration/query examples demonstrating:
  - indexed default
  - explicit Basic fallback
  - fuzzy option usage
- Align benchmark defaults with indexed backend and keep Basic comparison path.

Acceptance criteria:

- Search telemetry emits option metadata for both defaulted and custom requests.
- Telemetry contract docs reflect emitted metadata shape.
- README includes practical runtime examples for current default behavior.

---

### Phase 9: Backend Comparison Benchmark Harness

Objective:
Make performance validation repeatable for indexed vs basic search behavior.

Changes:

- Extend `scripts/search_benchmark.exs` with backend comparison mode:
  - `--backend both` runs indexed and basic in one execution.
  - per-query and overall summaries include `avg/p50/p95/min/max`.
  - comparison output reports basic/indexed p50 and p95 speedup ratios.
- Add warmup control for more stable timing:
  - `--warmup-iterations` (default `10`).
- Update README benchmark examples to include the comparison workflow.

Acceptance criteria:

- Benchmark script can run indexed-only, basic-only, and indexed-vs-basic modes.
- Output includes deterministic summary fields for each query and an overall aggregate.
- Comparison mode prints explicit speedup ratios for p50 and p95 latency.

---

### Phase 10: Corpus-Scale Benchmark Profiles and Memory Tracking

Objective:
Cover small/medium/large corpus performance scenarios and report memory growth.

Changes:

- Extend benchmark script with corpus profiles:
  - `--profile fixture` (existing fixture corpus)
  - `--profile small` (32 synthetic nodes)
  - `--profile medium` (256 synthetic nodes)
  - `--profile large` (1024 synthetic nodes)
- For synthetic profiles, generate temporary benchmark corpora automatically and
  clean them up after execution.
- Emit corpus/load metrics before query benchmarking:
  - node/edge/doc counts
  - term and posting key counts
  - cached body count
  - reload latency
  - memory before/after and delta
- Update README benchmark workflows with profile commands.

Acceptance criteria:

- Script can run profile benchmarks without manual fixture preparation.
- Output includes corpus-level memory and reload metrics.
- Small/medium/large profile commands are documented for repeatable perf checks.

---

### Phase 11: Multi-Profile Benchmark Sweep and Report Export

Objective:
Make cross-profile performance tracking easier to run and archive.

Changes:

- Extend benchmark profile mode with `--profile all` to run:
  - fixture
  - small
  - medium
  - large
  in a single command execution.
- Add suite-level summary output across profiles including:
  - corpus size
  - reload latency
  - memory delta
  - p50/p95 basic-vs-indexed speedup (when both backends are enabled)
- Add optional JSON report export via `--output <path>` for trend tracking.
- Update README with one-command sweep and report export usage.

Acceptance criteria:

- One command can benchmark all supported profiles sequentially.
- Output includes a suite summary line per profile.
- JSON report export is available for downstream analysis.

---

### Phase 12: Benchmark Guardrails and Regression Exit Codes

Objective:
Turn benchmark runs into enforceable quality gates for CI and release checks.

Changes:

- Add benchmark guardrail options:
  - `--min-speedup-p50`
  - `--min-speedup-p95`
  - `--max-memory-delta-mb`
  - optional `--enforce-profiles` selector
- Evaluate thresholds per profile and emit clear pass/fail diagnostics.
- Exit with non-zero status when guardrails fail.
- Include guardrail config/status/failures in JSON report export payload.
- Update README with guardrail command examples for CI usage.

Acceptance criteria:

- Benchmark can fail fast on configured speedup or memory regressions.
- Failures identify profile + metric + observed value + expected threshold.
- Exported report captures guardrail status for downstream automation.

---

### Phase 13: CI Benchmark Guardrail Automation

Objective:
Run benchmark guardrails automatically in CI and publish machine-readable reports.

Changes:

- Add `.github/workflows/benchmark-guardrails.yml` to execute benchmark checks on:
  - pull requests
  - pushes to `main`
  - manual workflow dispatch
- Run `scripts/search_benchmark.exs` with fixed CI thresholds and enforced profiles.
- Upload JSON report as a workflow artifact for audit/trend analysis.
- Add workflow summary output for guardrail status and failure diagnostics.
- Document the workflow in README so local and CI guardrails stay aligned.

Acceptance criteria:

- CI job fails when benchmark guardrails fail.
- Workflow always uploads benchmark JSON report artifact.
- Step summary includes guardrail status and any profile-level failures.

---

### Phase 14: Guardrail Evaluation Module and Unit Coverage

Objective:
Improve maintainability and confidence by moving benchmark guardrail logic into a
testable library module.

Changes:

- Add `Jido.Skillset.BenchmarkGuardrails` for:
  - threshold configuration detection
  - enforced profile selection
  - profile-level guardrail evaluation
  - guardrail status derivation
- Update `scripts/search_benchmark.exs` to call the shared module instead of
  inline guardrail logic.
- Add unit tests for pass/fail, missing-metric, profile-selection, and status
  behavior.

Acceptance criteria:

- Guardrail behavior remains unchanged for benchmark CLI consumers.
- Script and JSON report guardrail fields are driven by shared module functions.
- Unit tests validate guardrail evaluation edge cases without running benchmark
  end-to-end.

---

### Phase 15: Config-Driven Guardrail Thresholds

Objective:
Keep benchmark guardrail thresholds centralized and reusable across local runs
and CI workflows.

Changes:

- Add `--guardrail-config <path>` support to `scripts/search_benchmark.exs`.
- Load guardrail values from a JSON file when provided:
  - `min_speedup_p50`
  - `min_speedup_p95`
  - `max_memory_delta_mb`
  - `enforce_profiles`
- Keep CLI threshold arguments as explicit overrides over config-file values.
- Add `scripts/search_benchmark_guardrails.ci.json` as the tracked CI baseline.
- Update `.github/workflows/benchmark-guardrails.yml` to consume the config file
  and render summary thresholds from exported report JSON.
- Add config loader unit tests and README usage examples.

Acceptance criteria:

- Benchmark script accepts guardrail thresholds via JSON config file.
- Invalid/missing config file fails fast with a clear error.
- CI workflow no longer hard-codes threshold values in command flags.

---

### Phase 16: Strict Guardrail Config Validation

Objective:
Prevent silent guardrail misconfiguration by validating config-file values before
benchmark execution.

Changes:

- Extend `Jido.Skillset.BenchmarkGuardrails.Config` validation rules:
  - `min_speedup_p50` and `min_speedup_p95` must be numeric and `> 0`
  - `max_memory_delta_mb` must be numeric and `>= 0`
  - `enforce_profiles` must be an array of known profile names
- Normalize `enforce_profiles` entries to lowercase and deduplicate while
  preserving order.
- Return explicit `{:invalid_value, key, reason}` loader errors on invalid
  values.
- Add focused unit tests for invalid threshold ranges, invalid profile types,
  unknown profile names, and normalization behavior.
- Update README to clarify strict validation behavior.

Acceptance criteria:

- Invalid config values fail before benchmark execution begins.
- Error payload identifies the invalid key and reason.
- Config loader tests cover normalization and invalid-value paths.

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
