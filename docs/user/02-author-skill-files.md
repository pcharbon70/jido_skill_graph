# 02 - Author Skill Files

Create a folder for your skill graph:

```text
my_skills/
  graph.yml
  garden-basics/
    SKILL.md
  soil-prep/
    SKILL.md
```

## Define `graph.yml`

At minimum, set a `graph_id` and include pattern.

```yaml
graph_id: home-gardening
includes:
  - "**/*"
```

## Create a `SKILL.md`

Each skill document uses frontmatter plus markdown body content.

```md
---
title: Garden Basics
tags:
  - basics
  - planning
links:
  - target: soil-prep
    rel: prereq
  - target: watering
    rel: related
---
Start with a small plot and focus on consistent habits.

Use [[pest-check]] to catch problems early and [[compost]] to feed the soil.
```

## Notes

- `links` in frontmatter and wiki links like `[[other-skill]]` are both supported.
- Keep skill IDs stable by keeping folder names and explicit slugs consistent.
