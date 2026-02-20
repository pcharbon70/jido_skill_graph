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
Summary of the lesson: matching is not assignment in the imperative sense; it is a structural check that either succeeds and binds values or fails loudly.
The material highlights destructuring across tuples, lists, and maps, plus guardrails such as the pin operator when preserving an existing binding.

Pattern matching is used directly in [[control-structures]] (`case`/`with`) and function clause selection in [[functions]].
Before this topic, solidify collection fundamentals in [[basics]].
