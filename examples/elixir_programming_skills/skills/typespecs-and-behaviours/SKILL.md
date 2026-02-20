---
lesson_style: summary
title: Typespecs and Behaviours
tags:
  - elixir
  - contracts
  - architecture
links:
  - target: modules-and-docs
    rel: prereq
  - target: otp-supervision
    rel: related
  - target: testing
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/advanced/typespec
  - https://elixirschool.com/en/lessons/advanced/behaviours
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Typespecs communicate intended input/output contracts to humans and static analysis tools.
Even when runtime types are dynamic, clear specs reduce ambiguity in API usage.

Behaviours define callback contracts for pluggable modules.
They make architecture more modular by separating interface from implementation.
This is useful for adapters, test doubles, and framework boundaries.

When combined, typespecs and behaviours improve maintainability by making assumptions explicit.
They also help teams reason about module responsibilities as systems grow.

Use these techniques to keep OTP and application code consistent, testable, and easier to evolve.
