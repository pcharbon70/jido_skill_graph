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
`Enum` provides a rich toolkit for transforming lists and other enumerable data.
Map, filter, reduce, and chunk operations let you express intent clearly without manual loops.

The pipe operator (`|>`) turns nested calls into readable data flow.
Use it to show transformation steps from left to right, but keep each step meaningful.
If a pipeline becomes too long or opaque, extract helper functions.

Comprehensions are useful when building collections from one or more sources with concise filtering and projection.

These patterns are central to everyday Elixir and pair naturally with clean function design from [[functions]].
