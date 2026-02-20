---
lesson_style: summary
title: Testing with ExUnit
tags:
  - elixir
  - testing
  - quality
links:
  - target: mix-and-projects
    rel: prereq
  - target: error-handling
    rel: related
  - target: modules-and-docs
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/testing/basics
  - https://elixirschool.com/en/lessons/testing/mox
  - https://elixirschool.com/en/lessons/testing/stream_data
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
ExUnit provides a fast, expressive testing framework that integrates directly with Mix.
Write tests close to behavior, not implementation details.

A strong test suite covers pure functions, boundary conditions, and failure cases.
For side effects and external dependencies, use clear seams and mocking/stubbing only where needed.

Property-based testing is useful when invariants matter more than hand-picked examples.
As code grows, test organization and naming become as important as assertions.

Reliable tests support safe refactoring and make concurrency/error-handling changes less risky.
