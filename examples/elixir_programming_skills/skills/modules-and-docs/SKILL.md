---
lesson_style: summary
title: Modules and Documentation
tags:
  - elixir
  - structure
  - docs
links:
  - target: functions
    rel: prereq
  - target: mix-and-projects
    rel: related
  - target: testing
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/modules
  - https://elixirschool.com/en/lessons/basics/documentation
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Modules group related functions and define coherent API boundaries.
A good module name and function layout make code discoverable for both humans and tools.

Document public functions with `@doc`, include examples when behavior is non-obvious, and use `@moduledoc` to describe purpose and context.
When documentation is maintained as part of coding, onboarding and review speed improve.

Use module attributes for metadata and compile-time constants where appropriate, but avoid using them as mutable global state.

This structure becomes especially important in real projects managed with [[mix-and-projects]] and validated through [[testing]].
