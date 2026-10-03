---
id: 0044
title: One on-hit vocabulary for every attack mode — an OnHitEffect reads a mode-agnostic HitLanding, and a rider status is gated by the hit it is paired with
status: accepted
date: 2026-10-03
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "A mode needs an on-hit fact HitLanding cannot carry without a mode flag, or a rider must gate on something other than its paired hit landing"
sources:
  - "#1251"
  - "#1359"
  - "#1360"
  - "#1361"
  - "#495"
  - "attack/outcome/hit_landing.gd"
  - "attack/spell/on_hit/on_hit_effect.gd"
  - "attack/spell/on_hit/spell_on_hit_effect.gd"
  - "attack/outcome/status_instance.gd"
tags: [combat, on-hit, status, architecture]
---

# ADR 0044 — One on-hit vocabulary for every attack mode

## Context

`OnHitEffect` was spell-only: `apply(lctx: LandingContext)` reached into the cast's payload and ledger. Arrows applied their status through a ranged-only slot (`AmmoType.status_*` → `RangedStatusInstance`) and blades through a melee-only one (`BladeStatusInstance`), each with its own copy of "the status applies iff the primary hit landed". The code had read the #495 veto (*"magic will most likely NOT have anything to do with poison arrows"*, 2026-09-18) as "don't share on-hit logic across modes".

## Decision drivers

- One place to author an on-hit thing, whatever carries it.
- The spell path stays byte-identical: the characterization tests are the evidence.
- No type flag and no nullable spell field on the shared landing.

## Decision

Owner, 2026-10-03 on #1251, correcting that reading: *"The point was dead stats. For melee or magic a 'poison arrows per reload' stat would be dead. … So we removed those and instead created 'poison_aspect' … We absofuckenlutely want to share as much logic as we can"*. And, choosing a shared rider over the per-mode slots: *"OnHitEffect sounds like something i already thought all these status effect applications were authored with? If not then we should get that cleanliness ball running asap no matter the blast radius. … Authoring a new thing that applies? Drones would be like doing 1 grep: 'oh just slap that thing on it ggwp next'"*.

The shape below is the agent's pass (#1359, tentative where the owner did not speak to it):

- **`HitLanding`** (`attack/outcome/hit_landing.gd`) is the mode-agnostic landing: `attacker`, `source`, `origin`, `target`, `structural_key` (named after `HitInstance`'s fields), `paired` (the primary hit the landing rides on, or null) and `hits` (the sink emitted hits append to).
- **`OnHitEffect.apply(landing: HitLanding)`** is the one contract. Authoring a new on-hit thing means adding an `OnHitEffect` to the carrier's `on_hit_effects`.
- **`LandingContext extends HitLanding`**. A spell landing is a hit landing plus spell context. Effects that read spell context (`DamageEffect`, `HealEffect`, `ScaleDamageEffect`) extend the abstract **`SpellOnHitEffect`**, which narrows to `LandingContext` and does nothing on any other landing. `ApplyStatusEffect` reads only `HitLanding`, so it works in every mode.
- **`StatusInstance.paired`** is the one rider gate. If the paired hit did not land (`HitInstance.landed()`, by default `not gated`), the status lands as a power-0 dud flagged `gated`. A mode whose refusal is not a dud overrides `landed()`, as melee does with `admitted`. `paired` is never shipped: the authority already decided the gate, so a peer's rebuilt status has `paired == null` and lands its recorded power.

## Consequences

- Ranged (#1360) and melee (#1361) build a `HitLanding` per landing, run the carrier's `on_hit_effects` on it and delete `RangedStatusInstance` / `BladeStatusInstance`. Until they do, their old slots stand beside the new contract.
- `LandingContext.fill_landing()` derives the base fields from cast + payload, and they equal what the resolver stamps on the emitted hits. Its `hits` is the outcome's own array, by reference. A spell gates nothing, so its `paired` stays null.

## Alternatives considered

### A nullable `spell` field / a mode flag on one landing class
Every reader would need to branch on it. That is the parallel-mirrors shape the class split avoids. Dead.

### Per-mode status slots (the status quo)
The owner rejected these, quoted above. Dead.

### `ApplyStatusEffect` re-asking each mode's gate itself
A second `admit` of the same blade contact can pop a vertex twice (`BladeStatusInstance`'s own docstring). Reading the recorded verdict through `paired` is the only safe form. Dead.
