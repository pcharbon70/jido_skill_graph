---
lesson_style: summary
title: Control Structures
tags:
  - elixir
  - basics
  - flow
links:
  - target: pattern-matching
    rel: prereq
  - target: functions
    rel: related
  - target: error-handling
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/control_structures
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Elixir control structures emphasize expression-oriented flow.
`if` and `unless` are useful for simple booleans, while `case` and `cond` handle richer branching.

`case` is often the most idiomatic because it combines branching with pattern matching.
`with` is useful when you need a readable sequence of dependent matches and want to short-circuit on failure.

Prefer small functions with clear return values over large imperative blocks.
This keeps control flow testable and easier to reason about.

As programs grow, control structures blend with [[error-handling]] patterns such as tagged tuples and explicit success/error branches.
