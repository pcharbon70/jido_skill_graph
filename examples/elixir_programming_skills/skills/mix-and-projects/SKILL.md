---
lesson_style: summary
title: Mix and Project Workflow
tags:
  - elixir
  - tooling
  - build
links:
  - target: modules-and-docs
    rel: prereq
  - target: testing
    rel: prereq
  - target: typespecs-and-behaviours
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/mix
  - https://elixirschool.com/en/lessons/intermediate/mix_tasks
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Mix is the build tool and task runner for Elixir projects.
It manages dependencies, compilation, tests, and custom automation.

A project typically starts with `mix new`, then evolves through dependency setup, environment-specific configuration, and recurring tasks.
Custom Mix tasks are a clean way to encode operational workflows that teams run often.

Use aliases and standard task conventions to keep developer workflows predictable.
When everyone runs the same commands, onboarding and CI become simpler.

Mix ties together module organization, code quality, and release behavior across the rest of the graph.
