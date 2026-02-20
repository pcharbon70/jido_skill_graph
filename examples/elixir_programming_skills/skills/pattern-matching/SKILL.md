---
lesson_style: summary
title: Pattern Matching
tags:
  - elixir
  - basics
  - data-shaping
links:
  - target: basics
    rel: prereq
  - target: control-structures
    rel: related
  - target: functions
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/pattern_matching
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Pattern matching is one of Elixir's defining features.
You can destructure tuples, lists, and maps to bind only the pieces you care about.

A match succeeds when the value fits the pattern. If the shape is wrong, the match fails, which helps surface invalid assumptions early.
Use this behavior to make code explicit about expected input.

In function heads, pattern matching becomes a routing mechanism:
different clauses handle different shapes cleanly.
Combined with guards, this gives a concise way to express business rules without deeply nested conditionals.

Pattern matching works hand-in-hand with [[control-structures]] and [[functions]], and it appears constantly in [[concurrency]] message handling.
