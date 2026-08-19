---
paths:
  - "attack/plan/ranged_attack_plan.gd"
  - "test/unit/**/*ranged*"
  - "test/unit/**/test_presentation_hold.gd"
  - "test/unit/**/test_cascade_presentation_clock.gd"
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
volley (two `DamageInstance`s converging on the same target). #487 found this
the hard way — `SkillNode.presentation_hold`'s old boolean latch absorbed the
extra hit as a no-op, so tests asserting single-hit behavior passed for the
wrong reason for a long time. Now that the hold is a refcount (#487), a stray
second firing position makes a test's hold-count assertions fail (or, worse,
pass by coincidence if the test happens to emit exactly as many release
signals as there are real hits).

**How to apply:** in a fixture meant to be single-hit, either zero the
non-intended end's range (`_set_stat(core, &"range", 0.0)`) or assert
`plan.get_reaching_firing_positions().size() == 1` right after targeting, so a
silent second firing position fails loudly instead of masking itself. A
fixture that DELIBERATELY wants a multi-hit volley (see
`test_multi_hit_volley_reveals_one_arrow_at_a_time` in `test_presentation_hold.gd`)
should assert the firing-position count explicitly too, so it stays
intentional rather than accidental.
