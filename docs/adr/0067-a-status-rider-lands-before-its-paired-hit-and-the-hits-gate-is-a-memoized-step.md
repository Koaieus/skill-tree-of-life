---
id: 0067
title: A status rider lands before its paired hit — a landing-scoped per-hit priority applied as list position by the landing builder; the hit's land veto is a memoized gate step the first asker decides; refines 0049
status: accepted
date: 2026-10-17
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "a rider should CHANGE its hit's gate (an armor break blunting spikes before the contact) — a new design, out of scope here; or a second landing builder appears that cannot call HitLanding.place"
sources:
  - "#1688"
  - "#1562"
  - "#1561"
  - "attack/outcome/hit_instance.gd"
  - "attack/outcome/hit_landing.gd"
  - "test/unit/attack/test_rider_order.gd"
tags: [combat, on-hit, status, architecture]
---


# ADR 0067 — A status rider lands before its paired hit

## Context

ADR 0049 identifies riders by `hit_key` and gates them by `paired`; every mode appended a hit's riders after it, so a curse floor, armor break or hex reached only the hits *behind* it. Owner, 2026-10-11: *"as for all damage+status riders should use an advantageous application order"*. Owner picks, 2026-10-17 (`/swarmify` #1562): **status riders only** move (`StatusInstance`; paired damage, splash copies, blast, detonate and `CureInstance` stay after); a **two-step hit** (*"2 step sounds better composable"*); the order as **a per-hit priority, landing-scoped** (*"is a priority value on a Hit also an option?"* → yes).

## Decision

Refines 0049 (riders stay identified by `hit_key`, never adjacency); its "the later hits sharing its key" reads "the hits sharing its key".

1. **Priority.** `HitInstance.land_priority()` returns `LandPriority.BEFORE` (−1), `PRIMARY` (0) or `AFTER` (1). Base: `AFTER` iff `paired` is set, else `PRIMARY`; `StatusInstance` overrides to `BEFORE`. A spell's own authored hits ride nothing, so they stay `PRIMARY` in authored order — only infusion statuses move ahead of them.
2. **Placement is the landing builder's, deferred.** `HitLanding.anchor` is the span start (the paired hit's slot from `riding`; `pre` for a spell landing). `emit(hit)`, which every `OnHitEffect` writer calls, appends in authored order; the builder then calls `place()` once, a stable three-bucket partition of `hits[anchor..]`. Builders: `RangedDamageFormula.ride`, `SwingResolve` (before a charged piece's blast is armed), `SpellResolver` (after the riders, before stamping).
3. **Never a global sort key.** `OutcomeApplier.in_arrival_order` is untouched: within a beat the tiebreak is still list order, which `AttackRecord` ships and replays.
4. **The gate step.** `HitInstance.resolve_gate(world)` decides the veto once (base: none); `landed()` reads it after. `RangedHitInstance` moves `passes_gate` there (against its own target's slice — the asker may be a rider); `BladeDamageInstance` moves `LiveGate.admit`, its pop and `popped_vertex` there, keeping admit's once-per-event contract. Each `land_on` calls it first; `rider_gated(node, world)` asks `paired.resolve_gate(world)` before `paired.landed()`. A hand-set `gated` is honoured.

## Consequences

- A curse arrow deals at least its own raised floor; a hex can be spent by its own hit's crit (intended).
- A status landing first may decide its hit's gate — a spike pop then happens at the status's land, the same beat.
- Corruption's topple still resolves at the beat flush; Greed still spends at the rider's land; the crit stream is drawn in landing order on the authority only. The core-crack fall-through is ADR 0066's.
- A position-based reader of "the later hits sharing a key" (the arrow volley VFX's `riders_of`) no longer sees a status rider; read by key, not position.

## Alternatives considered

- **A global sort field read by `in_arrival_order`** — rejected: it would lift arrow 2's status ahead of arrow 1's damage in a shared beat, deciding arrow 2's gate before arrow 1 could kill its target, and touch the desync-sensitive order (#543 D2).
- **Insert-on-emit** — rejected: `SplashEffect` / `BlastEffect` stamp `land_mask` / `blast_mark` over `range(before, size)`, so an insert ahead of `before` would strip a splashed status's mask; and `DamageEffect` / `HealEffect` / `CureEffect` append straight to `cast.outcome.hits`, past any emit.
- **Re-identifying riders by adjacency** — already rejected by 0049.
- **A rider that changes its hit's gate** (armor break blunting spikes) — a new design, out of scope.
