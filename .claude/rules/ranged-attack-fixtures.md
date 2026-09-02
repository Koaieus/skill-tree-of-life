---
paths:
  - "attack/plan/ranged_attack_plan.gd"
  - "test/unit/**/*ranged*"
---

# Ranged attack fixtures

## `range`'s default is 400 — a two-node `core—leaf` chain fires from BOTH ends

`RangedAttackPlan.get_firing_positions()` returns `attacker.navigator.get_leaf_nodes()`
— graph-theoretic leaves (degree 1), not "the node literally named `leaf`". In
a fixture built as `core(0,0) — leaf(200,0)`, **both** ends have degree 1, so
both are firing positions. `stats_system/defs/range.tres` defaults to `400.0`,
which reaches almost anything at ordinary test-fixture distances (e.g. a
target at 250 away) — so `core` fires too unless its `range` is explicitly
capped, even though only `leaf`'s range was ever intentionally set.

**Why it matters:** this silently turns a "single hit" fixture into a 2-hit
volley (two `DamageInstance`s converging on the same target) — a test that
only meant to exercise one shot ends up asserting against `outcome.hits[0]`
while a second, unintended hit rides along unchecked.

**How to apply:** in a fixture meant to be single-hit, either zero the
non-intended end's range (`_set_stat(core, &"range", 0.0)`) or assert
`plan.get_reaching_firing_positions().size() == 1` right after targeting, so a
silent second firing position fails loudly instead of masking itself — see
`test_get_reaching_firing_positions_only_the_leaf_within_range` in
`test_ranged_attack_plan.gd` for the pattern. A fixture that DELIBERATELY
wants a multi-hit volley should assert the firing-position (or
`outcome.hits.size()`) count explicitly too, so it stays intentional rather
than accidental.
