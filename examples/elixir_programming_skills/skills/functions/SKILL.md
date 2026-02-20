---
lesson_style: summary
title: Functions
tags:
  - elixir
  - basics
  - functions
links:
  - target: basics
    rel: prereq
  - target: modules-and-docs
    rel: related
  - target: enum-and-pipe
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/functions
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Functions are the primary unit of abstraction in Elixir.
Named functions live in modules, while anonymous functions are useful for short callbacks and local transformations.

Prefer pure functions that accept data and return data.
This style improves composability and makes tests straightforward.
Function pattern matching in clauses can replace manual branching and make intent clear at the boundary.

Use default arguments sparingly and only when they improve readability.
When logic becomes dense, split it into small focused functions with meaningful names.

You will combine these ideas heavily with [[enum-and-pipe]] and organize them in [[modules-and-docs]].
