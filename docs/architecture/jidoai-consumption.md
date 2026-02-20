# JidoAI Consumption Model

This document describes how JidoAI should consume `jido_skill_graph` without
depending on graph internals.

## Principle

JidoAI calls only public APIs (or adapter wrappers) and does not own:

- parsing pipeline internals
- graph build internals
- snapshot storage internals

## Recommended Integration Surface

- `JidoSkillGraph.JidoAIAdapter.list_skill_candidates/2`
- `JidoSkillGraph.JidoAIAdapter.search_skills/3`
- `JidoSkillGraph.JidoAIAdapter.related_skills/3`
- `JidoSkillGraph.JidoAIAdapter.read_skill/3`

All of these calls route through public graph APIs.

## Example Flow

1. Load candidate skills:
   - list metadata (`list_skill_candidates/2`) with optional tag filters.
2. Rank or select:
   - search by query (`search_skills/3`) and/or traverse neighbors (`related_skills/3`).
3. Read selected skills on demand:
   - call `read_skill/3` only for skills chosen by orchestration policy.

This keeps selection policy in JidoAI while graph state/query behavior stays in
`jido_skill_graph`.
