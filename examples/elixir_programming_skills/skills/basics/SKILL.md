---
lesson_style: summary
title: Elixir Basics
tags:
  - elixir
  - basics
  - syntax
links:
  - target: pattern-matching
    rel: prereq
  - target: control-structures
    rel: prereq
  - target: functions
    rel: prereq
source_lessons:
  - https://elixirschool.com/en/lessons/basics/basics
  - https://elixirschool.com/en/lessons/basics/collections
  - https://elixirschool.com/en/lessons/basics/strings
  - https://elixirschool.com/en/lessons/basics/iex_helpers
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Elixir programs are built from immutable values. Numbers, strings, atoms, tuples, maps, and lists are the core data structures you use in almost every file.
When a value appears to "change," Elixir actually returns a new value and leaves the old one untouched.

Use IEx as your lab. Evaluate expressions, inspect values, and experiment with helper commands to understand function behavior quickly.
Collections are central: lists are great for sequential data, maps for key lookup, and tuples for fixed-size grouped values.

Mastering these basics makes later topics easier because every advanced feature still manipulates the same immutable building blocks.
From here, continue into [[pattern-matching]] and [[functions]].
