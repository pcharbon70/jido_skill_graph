# Versioning Policy

`jido_skill_graph` uses Semantic Versioning (`MAJOR.MINOR.PATCH`).

## Compatibility Rules

- `PATCH` releases fix bugs and documentation issues without intentional public
  API breaks.
- `MINOR` releases add backward-compatible features and new optional APIs.
- `MAJOR` releases may remove or change public APIs in incompatible ways.

## What Counts as Public API

- Functions and types exposed by `JidoSkillGraph` and documented adapter entry
  points.
- Runtime behavior guarantees documented in `docs/rfcs` and release notes.
- Telemetry event names and metadata contracts in
  `docs/architecture/telemetry-events.md`.

Internal modules and undocumented private behavior may change between releases.

## Deprecation Process

1. Mark APIs as deprecated in docs/specs.
2. Keep deprecated APIs through at least one `MINOR` release when feasible.
3. Remove deprecated APIs only in the next `MAJOR` release unless a security or
   correctness issue requires faster removal.
