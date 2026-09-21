---
id: 0027
title: An attack windup is an awaited presenter beat behind one contract for every mode, never a schedule offset; the director's shot is mode-agnostic
status: accepted
date: 2026-09-21
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "a mode needs a windup whose length depends on the compiled schedule (a per-hit lead rather than a beat before the loop)"
sources: ["#1040", "#559", "#866", "systems/battle_system.gd", "scenes/camera_director.gd", "attack/outcome/presentation_tempo.gd", "docs/domain/attack-timeline.md"]
tags: [combat, presentation, camera, architecture]
---

# ADR 0027 — An attack windup is an awaited presenter beat behind one contract for every mode, never a schedule offset; the director's shot is mode-agnostic

## Context

Melee stages its windup as an awaited `BeatClock` beat before the mutation loop
(`MeleePreview.begin_windup -> float`) and the camera director locks and follows
off melee-only signals and `_melee_*` state. Ranged and magic had the other
mechanism — `volley_draw_time` / `beat_lead_in` folded into every arrival by
`OutcomeSchedule.compile` — and the local seat was gated out of their framing.

## Decision drivers

- One interface per concern: a second staging mechanism next to melee's is a
  fork every future mode re-argues.
- The mutation clock must not start until the picture is ready, and must never
  wait on an animation (`.claude/rules/presentation-clock.md`).
- A windup is where a wire wait can hide (`await_record_ready`); an offset
  baked into the schedule cannot stretch.
- A zero-length windup must reproduce today's timing exactly.

## Decision

1. Every mode's presenter — `MeleePreview`, and each `VFXCoordinator` — exposes
   `begin_windup(plan, tempo) -> float` and `focus_marker() -> Node2D`;
   `BattleSystem` stages every mode through one `_stage_windup`, awaited on a
   `BeatClock` before `_apply_outcome`. The compiler adds no windup term.
2. The camera director's lock, follow, marker rebind and hold re-size are
   mode-agnostic; the shot is mandatory and hard-locked for every actor.

Owner (2026-09-21): *"If melee sets a precedent with its windup, ranged and
magic should ideally use the same interface or system."* — *"Same as melee: hard lock, every actor."*

## Consequences

- `volley_draw_time` leaves `launch_at` for the awaited beat; a coordinator is
  mounted at commit, before its windup.
- The seat predicate no longer reaches the attack path; it still gates commands.

## Alternatives considered

### Compile-time offset (the `beat_lead_in` precedent)
**Rejected** — lost on *one interface* and *hideable wire wait*: a second
staging mechanism, and a lead the record cannot stretch. Most likely to be
revived if a per-hit lead is ever needed; see `revisit-when`.

### Keep the seat gate for ranged/magic, lock only melee
**Rejected** — lost on *one interface*: two camera paths for one event.
