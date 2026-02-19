# JidoSkillGraph

`JidoSkillGraph` is a standalone Elixir library for building and querying markdown-based skill graphs.

## Phase 4 Status

This phase establishes discovery and parsing pipeline behavior:

- `JidoSkillGraph.Discovery` for `SKILL.md` / `skill.md` file discovery
- `JidoSkillGraph.SkillFile` for frontmatter and body parsing
- `JidoSkillGraph.LinkExtractor` for frontmatter + wiki link extraction
- `JidoSkillGraph.Builder` for link resolution, ambiguity handling, and snapshot assembly

## Development

Install toolchain and dependencies:

```sh
asdf install
mix deps.get
```

Run checks:

```sh
mix test
mix credo --strict
mix dialyzer
```
