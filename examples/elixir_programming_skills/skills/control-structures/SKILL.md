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
Summary of the lesson: prefer expression-oriented branching and explicit outcomes.
`if`/`unless` are simple boolean tools, while `case`, `cond`, and `with` are better for multi-branch and multi-step flows where data shape matters.
Guards narrow valid clauses and keep decision logic local to the pattern.

Use [[pattern-matching]] to power these branches, shape logic into reusable [[functions]], and map success/error paths into [[error-handling]] conventions.
