---
lesson_style: summary
title: Concurrency with Processes
tags:
  - elixir
  - concurrency
  - processes
links:
  - target: pattern-matching
    rel: prereq
  - target: error-handling
    rel: related
  - target: otp-supervision
    rel: prereq
source_lessons:
  - https://elixirschool.com/en/lessons/intermediate/concurrency
  - https://elixirschool.com/en/lessons/advanced/otp_concurrency
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Elixir concurrency is based on lightweight processes that communicate by message passing.
Each process has isolated state, which avoids shared-memory race conditions by design.

Use `spawn`, `send`, and `receive` to understand fundamentals.
Then move to abstractions like `Task` and `GenServer` when you need structure, lifecycle, and robust behavior.

Pattern matching is essential in message handling because it lets processes react to specific message shapes safely.
Failures should be expected; do not hide them with broad rescue logic.
Instead, design systems so failed processes can restart cleanly under supervision.

This leads directly into [[otp-supervision]].
