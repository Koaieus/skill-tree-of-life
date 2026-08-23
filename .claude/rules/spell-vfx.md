---
description: Spell VFX explanation
paths:
  - "attack/spell/defs/**"
  - "ui/vfx/**"
---

# Spell VFX

## Coordinator zoo

One per "shape" of action — see [docs/domain/attack_plan_system.md](../../docs/domain/attack_plan_system.md) for how `BattleSystem.launch_attack` picks them.

| Coordinator | Used by | Visual | Cadence knob |
|---|---|---|---|
| `MagicBounceCoordinator` (`ui/vfx/coordinator/magic_bounce_coordinator.gd`) | All magic spells (`SpellDef.vfx_coordinator_scene`) | `GlowingDot` (bouncy ball) | `beat_interval` |
| `ArrowVolleyCoordinator` (`ui/vfx/coordinator/arrow_volley_coordinator.gd`) | Ranged attacks (`AttackVFX.play_ranged_volley`) | `LightArrow` (oriented, sticks + fades) | `shot_flight_time` (defaults to `RangedDamageFormula.FLIGHT_TIME`; each shot's launch delay is recovered as `arrival_time - shot_flight_time` from the distance-authored ramp, never from its index — the reveal rides `DamageInstance.arrival_time`) |

## The clock contract (load-bearing)

`MagicBounceCoordinator` runs a **fixed cadence clock**: beat N fires at `t = N * beat_interval` regardless of what any visual is doing. Animations are given a normalized window and render into it; they may NOT gate the next wave.

**Why:** A slow fork of a fork-lightning spell would otherwise hold up the entire propagation — wrong shape. Multiple in-flight visuals stacking is the intended look for branchy spells.

**How to apply:**
- Per-beat emission is `wave_started(hop_index, events_in_wave)`. Tests assert on this signal — not on projectile-finished timing.
- Do NOT re-introduce `await previous-projectile-finished` style coupling between waves. The pattern was tried and rejected — see `test/unit/vfx/test_magic_bounce_coordinator.gd::test_hung_visual_does_not_delay_subsequent_waves`.
- `launch_to_impact` should default to slightly less than `beat_interval` so the projectile lands as the beat fires (small visual beat between waves).
- The coordinator still waits for all projectiles to drain before `play()` returns, so it doesn't `queue_free` mid-trail. That's a teardown-safety drain, not a wave gate.

## Three-clocks timing (#201)

Impact is pinned to the **beat**, not to launch. The coordinator spawns projectiles early (`beat_time - launch_to_impact`) so they arrive AT the beat:
- **Beat clock**: `wave_started` fires at `N * beat_interval` (the ground truth).
- **Travel clock**: projectile flies origin→target over `launch_to_impact` seconds.
- **Visual clock**: the visual's own windup/linger, free to start before launch and outlive impact. Authored via Godot's Animation dock with an Impact marker (4.3+) for complex visuals; lightweight visuals keep the duck-typed `_on_progress(t)` path.

`launch_to_impact` must be ≤ `beat_interval` for impact alignment. The old exports `per_hop_duration` / `flight_time` were renamed to reflect the semantic shift.

### There is a fourth clock, and it must agree: the mutation clock

`OutcomeApplier` lands each hit at its own `HitInstance.arrival_time` (#504), so
the world changes on a clock the coordinator does not own. **`arrival_time` means
"when the hit lands", absolutely — not "which wave it belongs to".**

Impact under three-clocks is `launch_to_impact + N * beat_interval`, so
`SpellResolver` stamps `WAVE_FLIGHT_LEAD_IN + hop_index * WAVE_ARRIVAL_INTERVAL`.
The two pairs of constants are deliberately *not* wired together (`resolve()` is
static and has no coordinator instance to read), so **retuning either export means
re-checking both constants.**

**Why the lead-in exists:** magic originally stamped `hop_index * interval`, i.e.
it omitted the flight. The mutation clock then ran a whole bolt-flight ahead of
the picture — the damage number, HP bar and node tint moved ~0.35 s *before* the
projectile arrived, most visibly on the seed, which landed at t=0 with the bolt
still in the air. Ranged never had this: a shot's `arrival_time` is its impact
moment and `ArrowVolleyCoordinator` recovers the launch delay as
`arrival_time - shot_flight_time`. Magic was the outlier; don't "simplify" the
offset back out.

A uniform offset shifts every hit equally, so wave ordering and the exact
within-wave ties that `OutcomeApplier.in_arrival_order` and `CritRoll`'s seeded
stream depend on are untouched.

## Verb → ProjectilePath mapping (#201)

Each `PropagationEvent.Verb` resolves to its own path and visual. Per-verb `@export` slots on the coordinator:

| Verb | Path export | Visual export | Default path shape |
|---|---|---|---|
| `JUMP` (seed) | `jump_path` | `jump_visual` | BezierArc (ignores edges) |
| `EDGE` (along edge) | `edge_path` | `edge_visual` | LinearPath (straight lerp) |
| `SELF_LOOP` | `self_loop_path` | `self_loop_visual` | SelfLoopPath (cubic teardrop) |
| `CANCEL` | (none — no projectile) | `cancel_visual` | CancelDissipate (in-place pop) |

Unset per-verb slots fall back to the legacy `projectile_path` / `visual_scene`, then to built-in defaults (`BezierArcPath` / `GlowingDot`).

### ProjectilePath catalogue

| Path | File | Use |
|---|---|---|
| `BezierArcPath` | `ui/vfx/projectile/path/bezier_arc_path.gd` | Quadratic arc through apex. Default for JUMP. |
| `LinearPath` | `ui/vfx/projectile/path/linear_path.gd` | Straight lerp origin→target. Canonical for EDGE. |
| `SelfLoopPath` | `ui/vfx/projectile/path/self_loop_path.gd` | Cubic Bezier teardrop loop. For SELF_LOOP (origin == target). |
| `CubicBezierPath` | `ui/vfx/projectile/path/cubic_bezier_path.gd` | General cubic with launch/arrival tangents. |
| `Curve2DPath` | `ui/vfx/projectile/path/curve2d_path.gd` | Authored `Curve2D` sampled and mapped. Used by AllocationVFX. |

## CANCEL dissipate (#201)

`CANCEL` events now spawn a one-shot dissolve effect at `ev.target`. The default is `CancelDissipate` (`ui/vfx/projectile/visual/cancel_dissipate.tscn`):
- Spawned in place at the target node.
- Scales up + fades out over `duration` (default 0.35 s).
- Emits `finished` when done, then `queue_free`s.
- Override via `cancel_visual` export; set to `null` to restore the old no-op behaviour.

## Visual contract (duck-typed)

Spawned by `Projectile`. Inbound methods (any subset, all optional):
- `_on_launch()` — once after delay clears
- `_on_progress(t: float)` — each frame, `t ∈ [0, 1]`
- `_on_arrival()` — once at impact

Outbound:
- `finished` signal — visual says "I'm fully drained, safe to free". Missing → `Projectile.linger_seconds` fallback.

Tint hook: `ArrowVolleyCoordinator` stamps `tint: Color` on the visual right after `proj.launch()` (when `_visual` is already a child). Visuals without a `tint` field ignore it.

## The coordinator reads `outcome.timeline`, not `outcome.hits` (#46)

`MagicBounceCoordinator` walks `AttackOutcome.timeline: Array[PropagationEvent]`
(grouped by `beat`), not `_group_by_hop(hits)`. Each event carries a movement
`verb` (`JUMP`/`EDGE`/`SELF_LOOP`/`CANCEL` — the a/b/e/d vocabulary), its
`origin`/`target` nodes, and `hits: Array[HitInstance]` (shared refs into
`outcome.hits`; empty for `CANCEL` and zero-damage landings — #381 collapsed
the old nullable `damage`/`heal` pair + event-owned `crit_tier` into this one
list). Crit tier lives on each hit now; read `event.max_crit_tier()` for the
per-event emphasis value.

**Why the guard is `timeline.is_empty()`, not `hits.is_empty()`:** a pure-utility
spell (`power` 0) produces events with no hits — it must still render its
path. Gating on `hits` would silently no-op it.

`outcome.hits` is still the universal flat list every attack type appends to
(melee/ranged/spell, damage and heals together); the timeline is **additive
spell structure over the same `HitInstance` objects**, not a replacement.
Branch per-hit on `HitInstance.kind` (`DAMAGE`/`HEAL`) to route the reveal —
`_show_presentation` in the coordinator is the reference implementation. Full
rationale + the verb table live in
[docs/domain/spell-propagation.md](../../docs/domain/spell-propagation.md)
(update its `damage`/`heal` field references too).

## Spell-playground gotcha — retired, do not re-add

The spell playground used to typecheck for `MagicBounceCoordinator` and patch its
`apex_height` from 420 down to 70, because a production-scale arc left the top of
a ~340 px panel and read as "no projectile, damage just appeared". That per-type
override is **gone**, and a new coordinator type needs no equivalent: the panel
now fits its world by scaling the `Graph` node rather than by moving nodes, and
`AttackVFX` is parented under that same `Graph` — so an arc is as tall relative to
the board as it is in game, whoever draws it.
