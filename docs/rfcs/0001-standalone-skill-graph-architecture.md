# RFC 0001: Standalone Skill Graph Architecture for Jido Ecosystem

- Status: Proposed
- Authors: Jido maintainers
- Date: 2026-02-19
- Phase: 1 (Architecture Lock)
- Source: `notes/research/skill_graph_architecture.md`

## 1. Context

The current direction requires a reusable skill graph capability that is not coupled to any single agent runtime. The architecture research proposes that graph loading, parsing, topology, and query APIs live in an independent Elixir package, while runtimes consume it via adapters.

This RFC locks boundaries before implementation so later phases can ship incrementally with clear ownership and stable integration points.

## 2. Problem Statement

Jido ecosystem components currently risk mixing concerns:

- Graph storage and query mechanics
- Runtime-specific orchestration decisions

If these are not split early, the system becomes hard to evolve, test, and publish independently.

## 3. Goals

- Build `jido_skillset` as a standalone library (Hex + Git repo compatible).
- Keep runtime integrations as consumers through adapters.
- Support both supervised and pure-library usage patterns.
- Preserve compatibility with common skill markdown conventions.

## 4. Non-Goals

- This phase does not implement runtime behavior.
- This phase does not define LLM prompting or tool selection policy.
- This phase does not define application-level orchestration policy.

## 5. Decision Summary

We adopt the following architecture:

- Core package: `jido_skillset`
  - Owns discovery, parse pipeline, graph build, snapshot storage, query API.
- Jido adapter layer
  - Owns supervision integration and Jido signal emission.

## 6. Package Boundaries

### 6.1 `jido_skillset` owns

- Skill file loading (`SKILL.md`, `skill.md`) and optional manifests (`graph.yml`).
- Frontmatter parsing + markdown link extraction.
- Directed graph topology (cycles allowed).
- Snapshot model and atomic reload behavior.
- Public query API:
  - list graph metadata and topology
  - read node metadata
  - traverse node links and neighbors
  - read node body lazily
  - baseline search

### 6.2 `jido_skillset` does not own

- LLM orchestration policies.
- Agent runtime assumptions specific to Jido internals.
- Assistant UI/registry semantics beyond interoperable markdown parsing.

### 6.3 Runtime adapters own

- Runtime wiring into supervisors.
- Signal publishing and telemetry forwarding.
- Application-level selection logic for when and how graph APIs are called.

## 7. Operating Modes

`jido_skillset` must support both:

- Supervised mode: exposes `child_spec/1` and manages in-memory snapshot lifecycle.
- Pure mode: exposes `Builder.build/1` that returns immutable snapshot structs.

## 8. Compatibility Requirements

The parser contract must support:

- Optional YAML frontmatter.
- Markdown bodies.
- Typed links in frontmatter.
- Wiki links (`[[node]]`) and optional typed conventions (`[[prereq:node]]`, `[[extends:node]]`).

## 9. Risks and Mitigations

- Ambiguous link resolution:
  - Mitigate with canonical node IDs and deterministic normalization rules.
- Runtime coupling creep:
  - Mitigate by enforcing adapter boundaries and package ownership checks in code review.
- Reload instability:
  - Mitigate with snapshot swap semantics and failure isolation.

## 10. Alternatives Considered

- Keep graph inside a runtime namespace:
  - Rejected because it blocks reuse and couples to one runtime.

## 11. Rollout Strategy

- Implement one phase per PR.
- Keep each phase independently reviewable and mergeable.
- Use adapter integration only after core contracts are stable.

## 12. Exit Criteria for Phase 1

- Boundaries approved and documented.
- Ownership map committed.
- v0.1 acceptance criteria committed and agreed.
