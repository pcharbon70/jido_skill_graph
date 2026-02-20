---
lesson_style: summary
title: OTP Supervision and Resilience
tags:
  - elixir
  - otp
  - supervision
links:
  - target: concurrency
    rel: prereq
  - target: error-handling
    rel: related
  - target: typespecs-and-behaviours
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/advanced/otp_supervisors
  - https://elixirschool.com/en/lessons/advanced/behaviours
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
OTP supervision is Elixir's primary mechanism for fault-tolerant systems.
Supervisors monitor child processes and apply restart strategies when failures occur.

Instead of trying to prevent every crash, design components that can restart from known state.
This "let it crash" mindset works when process boundaries are clear and supervision trees reflect system domains.

Choose restart strategies intentionally (`:one_for_one`, `:rest_for_one`, `:one_for_all`) based on dependency direction.
Keep child initialization small and deterministic to reduce restart complexity.

Supervision works best when each worker has a clear contract, which can be formalized with [[typespecs-and-behaviours]].
