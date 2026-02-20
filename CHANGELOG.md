# Changelog

All notable changes to `jido_skill_graph` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Removed repository-owned MCP functionality.
- Removed JidoAI-specific coupling from core package and docs.

## [0.1.0] - Draft

### Added

- Standalone graph package with `SKILL.md`/`skill.md` discovery and parsing.
- Directed graph snapshot build pipeline with atomic reload swaps.
- Public query APIs for topology, metadata, traversal, and lazy body reads.
- Pluggable search backend behavior and baseline search implementation.
- Optional Jido adapter and event publishing hooks.
- Telemetry contracts and architecture/release documentation.
