---
description: Degree inside a spell resolve or a blade sim — the world-aware accessors, never SkillNode's
paths:
  - "attack/spell/**"
  - "attack/outcome/**"
  - "attack/plan/**"
  - "attack/melee/**"
---
Inside a spell resolve, entity degree goes through `PropagationContext.entity_degree_of(node)` / `LandingContext.entity_degree_of(node)`, never `SkillNode.get_entity_degree` directly — ownership can move mid-cast (a node this same cast deallocated on an earlier wave) and only the world-aware accessor sees that.

A blade vertex's degree is neither of those — it's degree within `state.edges` (the phantom blade's own induced subgraph, braces excluded — `ClampAddon` contributes to `state.constraints`, never `state.edges`), so walk `BladeState.edges`/`BladePopResolver._build_adjacency` directly. See docs/domain/degree.md
