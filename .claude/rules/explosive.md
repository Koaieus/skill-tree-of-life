---
paths:
  - "elements/disc_go_off.gd"
  - "attack/melee/sim/blade_pop_resolver.gd"
---

A hit that plants explosive (a `PlantUse` rider) never sets go-off zero off — `HitGather._plants` skips it; and a blade contact's gate spends the piece alone, never the struck node — the node's charges are the gather's. See docs/domain/explosive.md
