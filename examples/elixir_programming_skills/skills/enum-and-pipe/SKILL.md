---
lesson_style: summary
title: Enum and Pipe Operator
tags:
  - elixir
  - collections
  - transformations
links:
  - target: functions
    rel: prereq
  - target: basics
    rel: prereq
  - target: mix-and-projects
    rel: related
source_lessons:
  - https://elixirschool.com/en/lessons/basics/enum
  - https://elixirschool.com/en/lessons/basics/pipe_operator
  - https://elixirschool.com/en/lessons/basics/comprehensions
content_origin: Summarized from Elixir School lessons in paraphrased form. Not verbatim text.
---
Summary of the source lessons: favor declarative collection processing with `Enum` and represent transformations as readable pipelines.
Use comprehensions for dense iteration/filter/projection cases, and reserve long pipelines for steps that remain semantically clear.

These patterns depend on stable data assumptions from [[basics]] and function boundaries from [[functions]].
In real applications, they are combined and automated through [[mix-and-projects]] workflows.
