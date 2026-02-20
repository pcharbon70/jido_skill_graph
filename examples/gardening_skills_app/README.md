# Gardening Skills App

This example application loads a defined skills graph about home gardening and
runs a set of sample queries.

## Run

From the repository root:

```sh
mix run examples/gardening_skills_app/run.exs
```

## What It Demonstrates

- loading a graph from `examples/gardening_skills_app/skills`
- listing graph metadata and topology
- listing nodes with and without tag filters
- traversing out-links and neighbors
- searching nodes by terms
- lazily reading node body content with frontmatter
