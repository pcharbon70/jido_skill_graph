# 01 - Getting Started

`Jido.Skillset` is an Elixir library for building and querying markdown-based skill graphs.

## Prerequisites

- Elixir `>= 1.17`
- Erlang/OTP `>= 27`

## Install Dependencies

From the repository root:

```sh
asdf install
mix deps.get
```

## Run a Quick Example

Run the gardening demo:

```sh
mix run examples/gardening_skills_app/run.exs
```

Run the Elixir learning graph demo:

```sh
mix run examples/elixir_programming_skills/run.exs
```

Both scripts load a graph and execute common query/search calls so you can verify your environment end-to-end.
