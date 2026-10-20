---
paths:
  - "attack/spell/on_hit/detonate_effect.gd"
  - "attack/melee/sim/blade_pop_resolver.gd"
---

A hit that lands explosive (a `PlantUse` rider) never blasts — `DetonateEffect.arm` skips it; and a blade contact's node side (`present + r·shared`) only reaches blade pieces, never the board. See docs/domain/explosive.md
