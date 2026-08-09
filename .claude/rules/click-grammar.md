---
description: Click grammar quick-reference — left arms/resolves, right pops one level
paths:
  - "attack/plan/**"
  - "systems/player_input_controller.gd"
  - "systems/battle_system.gd"
---

Left-click always pushes forward (arms/sets origin/resolves a target); right-click always pops exactly one level off the plan's state stack, ignoring which node was clicked; a left-click on the origin that fails the mode's own target-validity check falls through to the same `pop()` instead of a denial. See docs/design/click_grammar.md.
