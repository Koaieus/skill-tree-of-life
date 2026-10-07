---
paths:
  - "ui/vfx/projectile/visual/arrow_parts/**"
  - "ui/vfx/projectile/visual/arrows/**"
  - "attack/ammo/types/**"
---
An arrow look is a pure `.tscn` of kit parts (`arrow_parts/`) in slots or child nodes: a missing behaviour widens a part with an export, a new part class only for behaviour two looks share, and a look-root `.gd` only for cross-part coordination unique to that look, with the reason stated on its issue. See docs/domain/aspect-cell-authoring.md § Arrow.
