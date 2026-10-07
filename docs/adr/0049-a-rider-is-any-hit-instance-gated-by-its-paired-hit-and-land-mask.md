---
id: 0049
title: A rider is any HitInstance — hit_key, paired and the land mask live on the base, and the riders of a hit are the later hits sharing its key — supersedes 0044
status: accepted
date: 2026-10-07
deciders: owner+agent
supersedes: [0044]
superseded-by: null
revisit-when: "The land mask (tentative pass) needs a check other than an ownership bit, or a rider must find its primary by something other than a shared landing key"
sources:
  - "#1478"
  - "#1480"
  - "#1482"
  - "docs/adr/0044-one-on-hit-vocabulary-for-every-attack-mode.md"
  - "attack/outcome/hit_instance.gd"
  - "attack/formulas/ranged_damage.gd"
  - "ui/vfx/coordinator/arrow_volley_coordinator.gd"
tags: [combat, on-hit, status, architecture]
---

# ADR 0049 — A rider is any HitInstance

## Context

ADR 0044 made `StatusInstance.paired` the one rider gate: "a rider *status* is gated by the hit it is paired with". The splash flare added a second clause on the status alone (`require_hostile`), and `hit_key` lived on `StatusInstance` too. The arrow itself had no key, so the volley coordinator found "the riders of arrow i" by adjacency (`while hits[j] is StatusInstance`). #1482's rider is a `DamageInstance`: it must dud with its arrow and re-check hostility like a splashed status, and adjacency cannot see it.

## Decision drivers

- A damage rider and a status rider gate identically, in one place.
- The wire shape and the save format stay unchanged (`AttackRecord` already ships a key per hit).
- A replay never re-decides a gate the authority decided.

## Decision

Owner, 2026-10-07 on #1478 (F3), as recorded there: **`hit_key` moves up to `HitInstance`**, and riders become "hits sharing the arrow's key" — picked over keeping an adjacency helper. The same pass lifts the rest of the rider gate (`paired`, the land mask) to `HitInstance`; that lift is the agent's pass, **tentative**:

- `HitInstance` owns `paired`, `hit_key` and `land_mask` (an int over `SkillNode.Ownership`, `0` = no recheck; it replaces `StatusInstance.require_hostile`). `rider_gated(node)` is the one gate `StatusInstance.land_on` and `DamageInstance.land_on` consult: gated iff `paired` did not land, or the mask is set, the hit is not `land_resolved`, and the node's ownership bit to the attacker misses the mask.
- `RangedDamageFormula.riders_for` stamps the arrow with its landing's key. A bare arrow mints no landing and stays `hit_key == 0`, and `0` matches nothing.
- `AttackRecord` ships `hit_key` on every hit and marks every rebuilt hit `land_resolved`. `paired` and `land_mask` are never shipped.

Everything else in ADR 0044 (`HitLanding`, `OnHitEffect.apply(landing)`, `SpellOnHitEffect`, `landed()` overrides) stands unchanged.

## Consequences

- Any `OnHitEffect` may emit a damage, heal or status rider; it duds with its primary and honours a land mask with no per-kind code.
- `ArrowVolleyCoordinator.riders_of(hits, i, same_target)` is the one rider lookup; a splashed rider on another node is found, which adjacency on the target could not promise.
- The record's `status_keys` field and its `h_skey` wire key keep their names though they now carry every hit's key.

## Alternatives considered

### Keep an adjacency helper (riders = hits appended right after the arrow)
Loses on the first driver: it is a convention of `riders_for`'s append order, not a fact on the hit, and breaks the moment a rider is not a `StatusInstance`. The owner rejected it, above. The most likely to be revived, if keys ever stop being unique per landing.

### A per-kind gate (`require_hostile` on each rider class)
Loses on the first driver: two copies of one rule, drifting. Dead once a second rider kind exists.

### Ship `land_mask` and re-check on the peer
Loses on the third driver: the peer would re-decide against its own view of ownership. Dead (ADR 0002's replay rule).
