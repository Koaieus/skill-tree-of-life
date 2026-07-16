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
| `ArrowVolleyCoordinator` (`ui/vfx/coordinator/arrow_volley_coordinator.gd`) | Ranged attacks (`AttackVFX.play_ranged_volley`) | `LightArrow` (oriented, sticks + fades) | `stagger_per_shot` |

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
`origin`/`target` nodes, a **nullable** `damage` (shared ref into `hits`; null for
`CANCEL` and zero-damage landings), and `crit_tier` (0 until crits ship).

**Why the guard is `timeline.is_empty()`, not `hits.is_empty()`:** a pure-utility
spell (base_damage 0) produces events with no damage — it must still render its
path. Gating on `hits` would silently no-op it.

`hits` is still the universal flat list every attack type appends to (melee /
ranged / spell); the timeline is **additive spell structure over the same
`DamageInstance` objects**, not a replacement. Apply HP only when
`event.damage != null`. Full rationale + the verb table live in
[docs/domain/spell-propagation.md](../../docs/domain/spell-propagation.md).

## Spell-playground gotcha

The playground's viewport is small; production `BezierArcPath.apex_height = 420` sends the projectile off-screen. `addons/spell_playground/playground_panel.gd` typechecks for `MagicBounceCoordinator` and overrides the arc to `apex_height = 70`. If you add a new coordinator type for the playground, repeat the override or projectiles disappear.
