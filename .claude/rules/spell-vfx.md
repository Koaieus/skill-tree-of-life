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
| `MagicBounceCoordinator` (`ui/vfx/coordinator/magic_bounce_coordinator.gd`) | All magic spells (`SpellDef.vfx_coordinator_scene`) | `GlowingDot` (bouncy ball) | `per_hop_duration` |
| `ArrowVolleyCoordinator` (`ui/vfx/coordinator/arrow_volley_coordinator.gd`) | Ranged attacks (`AttackVFX.play_ranged_volley`) | `LightArrow` (oriented, sticks + fades) | `stagger_per_shot` |

## The clock contract (load-bearing)

`MagicBounceCoordinator` runs a **fixed cadence clock**: hop N's wave fires at `t = N * per_hop_duration` regardless of what any visual is doing. Animations are given a normalized window and render into it; they may NOT gate the next wave.

**Why:** A slow fork of a fork-lightning spell would otherwise hold up the entire propagation — wrong shape. Multiple in-flight visuals stacking is the intended look for branchy spells.

**How to apply:**
- Per-hop emission is `wave_started(hop_index, hits_in_wave)`. Tests assert on this signal — not on projectile-finished timing.
- Do NOT re-introduce `await previous-projectile-finished` style coupling between waves. The pattern was tried and rejected — see `test/unit/vfx/test_magic_bounce_coordinator.gd::test_hung_visual_does_not_delay_subsequent_waves`.
- `flight_time` should default to slightly less than `per_hop_duration` so the ball lands as the next wave fires (small visual beat between hops).
- The coordinator still waits for all projectiles to drain before `play()` returns, so it doesn't `queue_free` mid-trail. That's a teardown-safety drain, not a wave gate.

## Visual contract (duck-typed)

Spawned by `Projectile`. Inbound methods (any subset, all optional):
- `_on_launch()` — once after delay clears
- `_on_progress(t: float)` — each frame, `t ∈ [0, 1]`
- `_on_arrival()` — once at impact

Outbound:
- `finished` signal — visual says "I'm fully drained, safe to free". Missing → `Projectile.linger_seconds` fallback.

Tint hook: `ArrowVolleyCoordinator` stamps `tint: Color` on the visual right after `proj.launch()` (when `_visual` is already a child). Visuals without a `tint` field ignore it.

## Spell-playground gotcha

The playground's viewport is small; production `BezierArcPath.apex_height = 420` sends the projectile off-screen. `addons/spell_playground/playground_panel.gd` typechecks for `MagicBounceCoordinator` and overrides the arc to `apex_height = 70`. If you add a new coordinator type for the playground, repeat the override or projectiles disappear.
