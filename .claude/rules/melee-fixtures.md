---
paths:
  - "attack/melee/**"
  - "attack/plan/melee_attack_plan.gd"
  - "addons/melee_sandbox/**"
  - "scenes/dev/melee_sandbox_graph.tscn"
  - "test/unit/**/*melee*"
  - "test/unit/**/*blade*"
---

# Melee fixtures: a swing that animates and hits nothing

Three ways to build a melee scenario whose swing looks perfect and lands zero
hits. All three are silent — no error, no warning, an empty `last_events`.

## 1. Both entities default to the same faction, so the target is ALLIED

`Entity.faction` defaults to `npc.tres`. `attitude_to` compares faction **ids**,
so two entities that never set one are **allies** — and
`MeleeAttackPlan.collect_target_excludes()` drops MINE|ALLY colliders *before the
scan queries them*. The whole enemy territory is invisible to the blade.

**How to apply:** author a faction on at least one side of any melee fixture
(`res://entity/factions/player.tres` vs the `npc` default). Same trap for any
`ownership_bit`-gated feature; melee is just where it costs you a whole swing.

## 2. A blade WHIPS — effective reach ≪ pivot-to-tip span

Only pivot-adjacent particles get a `BladeArcDriver`; everything further out is
dragged by distance constraints, so it lags and pulls inward. Measured on a
5-member blade spanning 319 px: peak reach ~275 px, and as little as **72 px** on
angles the swing has already passed. A target placed at the static span is
geometrically "inside the blade" and is never touched.

**How to apply:** place targets at roughly **¾ of the pivot-to-tip span**, never
at the span itself, and if a swing mysteriously misses, print each vertex's
min/max radius over `trajectory.samples` before touching anything else. Nothing
asserts this — a bound on the melee sandbox's layout was tried and deleted,
because it went red on every deliberate rearrange of a scratchpad.

## 3. Hit detection is a physics sweep, so a dormant world hits nothing

`BladeHitScan` queries the **2D physics server** (areas only, bodies off) — and
since #811 so does the defender field: `BladeDefenderZones.query()` is one
`intersect_shape` against the `swing_drag` / `deflection` collision bits, so a
fortified or bunkered node the physics space has not seen yet simply does not
defend, with no error. So a fixture needs `await get_tree().physics_frame`
before swinging — one
`process_frame` is not enough — and anything that sets `PROCESS_MODE_DISABLED` on
the world (the melee sandbox tab does exactly that when its tab is hidden) takes
those Area2Ds out of the broadphase entirely.

Two extra teeth since #811: a node's defender bits are driven by
`SkillNode._sync_defender_bit` off the stat's local value, so **attach the addon
and then `await get_tree().physics_frame`** — attaching after the last physics
frame leaves the bit set but the query already run. And a defender placed at the
blade's *rest* span is no longer culled (that was #808's bug) but a defender
placed where the blade never actually goes still never contacts; place it on a
point read off the free swing's own trajectory, as
`test_blade_whip_reach.gd` and `test_bunker_break_live.gd` both do.
