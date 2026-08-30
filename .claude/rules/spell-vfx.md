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
| `MagicBounceCoordinator` (`ui/vfx/coordinator/magic_bounce_coordinator.gd`) | All magic spells (`SpellDef.vfx_coordinator_scene`) | `GlowingDot` is the built-in *fallback*; every spell should select from the shared kit below (#670) | `beat_interval` |
| `ArrowVolleyCoordinator` (`ui/vfx/coordinator/arrow_volley_coordinator.gd`) | Ranged attacks (`AttackVFX.play_ranged_volley`) | `LightArrow` (oriented, sticks + fades) | `shot_flight_time` (defaults to `RangedDamageFormula.FLIGHT_TIME`; each shot's launch delay is recovered as `arrival_time - shot_flight_time` from the distance-authored ramp, never from its index — the reveal rides `DamageInstance.arrival_time`) |

## The clock contract (load-bearing)

`MagicBounceCoordinator` runs a **fixed cadence clock**: beat N fires at `t = N * beat_interval` regardless of what any visual is doing. Animations are given a normalized window and render into it; they may NOT gate the next wave.

**Why:** A slow fork of a fork-lightning spell would otherwise hold up the entire propagation — wrong shape. Multiple in-flight visuals stacking is the intended look for branchy spells.

**How to apply:**
- Per-beat emission is `wave_started(hop_index, events_in_wave)`. Tests assert on this signal — not on projectile-finished timing.
- Do NOT re-introduce `await previous-projectile-finished` style coupling between waves. The pattern was tried and rejected — see `test/unit/vfx/test_magic_bounce_coordinator.gd::test_hung_visual_does_not_delay_subsequent_waves`.
- `launch_to_impact` should default to slightly less than `beat_interval` so the projectile lands as the beat fires (small visual beat between waves).
- The coordinator still waits for all projectiles to drain before `play()` returns, so it doesn't `queue_free` mid-trail. That's a teardown-safety drain, not a wave gate.

## Three-clocks timing (#201, retuned by #543)

Impact is pinned to the **beat**, not to launch — each projectile is spawned one
lead-in early so it arrives AT the beat:
- **Beat clock**: `wave_started` fires at `lead_in + N * beat_interval` (the ground truth).
- **Travel clock**: the projectile flies origin→target over `lead_in` seconds.
- **Visual clock**: the visual's own windup/linger, free to start before launch and outlive impact. Authored via the Animation dock with an Impact marker (4.3+) for complex visuals; lightweight ones keep the duck-typed `_on_progress(t)` path.

**Since #543 all three read one authored source.** `beat_interval` and
`beat_lead_in` live on a `PresentationTempo` resource (`attack/outcome/`),
referenced from `SpellDef.tempo` with **one shared default `.tres`**.
`MagicBounceCoordinator` exports neither: it reads
`outcome.schedule.beat_interval()` / `.lead_in()` off the compiled
`OutcomeSchedule`, and its own `tempo` export is a **fallback for a hand-built
outcome only**. Retune a spell by editing its `.tres` — never a constant in
code, never a coordinator export (that moves the picture and leaves the model
behind). The compiler clamps the lead-in to the interval: a longer one would
launch wave N+1 before wave N landed. The player-facing **rate**
(`GameSettings.combat_time_scale`) is a separate multiplier folded in after
every shape term; it is per-peer and may legally differ between two machines.

### There is a fourth clock: the mutation clock — and it can no longer disagree

`OutcomeApplier` lands each hit at its own `HitInstance.arrival_time` (#504), so
the world changes on a clock the coordinator does not own — **`arrival_time` is
"when the hit lands", absolutely, not "which wave it belongs to".** It used to be
kept in step with the picture by hand: `SpellResolver` stamped
`WAVE_FLIGHT_LEAD_IN + hop_index * WAVE_ARRIVAL_INTERVAL` from its own `const`s
while the coordinator drew from its own `@export`s, unwired — retuning either
meant re-checking both. That tax is gone: the resolver records only the hop
**ordinal**, `OutcomeSchedule.compile` is the sole writer of seconds, and the
coordinator reads the schedule it wrote.

**Why the lead-in still exists** (do not "simplify" it back out): magic once
stamped `hop_index * interval`, omitting the flight, so the mutation clock ran a
whole bolt-flight ahead of the picture — damage number, HP bar and node tint all
moved ~0.35 s *before* the projectile arrived, most visibly on the seed, which
landed at t=0 with the bolt still in the air. But **seconds are presentation;
ORDER is structure**: landing order and `CritRoll`'s seeded stream key off
`HitInstance.schedule_index`, never off `arrival_time`, which is tempo-dependent
and so per-peer. Sorting on the float is a desync that reports a green suite;
`test_outcome_schedule.gd` scans for a reintroduced one.

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
| `WavePath` | `ui/vfx/projectile/path/wave_path.gd` | Lerp + transverse sine (#670 P3). "This propagates" rather than "this was thrown". Reverberator / Resonator. |
| `JitterPath` | `ui/vfx/projectile/path/jitter_path.gd` | Lerp + perpendicular hash noise (#670 P4). Unstable arcing electricity. Spark / the lightning family. |

**The shared primitive kit (#670)** — `BoltBody` (+5 configs), `ImpactRing`,
`WavePath`, `JitterPath`, `EdgeEnergize`, plus an **ease knob on every path**
(remaps *time*, not shape). Never a per-instance `ShaderMaterial` nor animated
per-instance uniform (the kit batches ~60 into one draw); the crit grammar is
authored ONCE in `ImpactRing`; `EdgeEnergize` paints on top, never touching the
edge MultiMesh. [docs/domain/spell-vfx-kit.md](../../docs/domain/spell-vfx-kit.md).

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
