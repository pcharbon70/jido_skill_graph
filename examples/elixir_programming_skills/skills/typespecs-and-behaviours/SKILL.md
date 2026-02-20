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
Summary of the source lessons: typespecs document expectations and improve analysis tooling, while behaviours formalize callback contracts for interchangeable modules.
Together they support safer extension points and clearer API communication across teams.

Document these contracts where modules are defined in [[modules-and-docs]], apply them to long-lived service boundaries in [[otp-supervision]], and verify contract adherence in [[testing]].
