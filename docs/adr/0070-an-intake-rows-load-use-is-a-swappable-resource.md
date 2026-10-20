---
id: 0070
title: How a hit spends an intake row's load is a swappable `LoadUse` resource on the row (`PlantUse` / `DetonateUse` / `FuelUse`, null = the concept status's default), filling one per-cast `LoadBag` — supersedes 0061's face enum and 0060's "one ApplyStatusEffect per concept" in part
status: accepted
date: 2026-10-20
deciders: owner (load is a dict the spell spends as it likes; the default plants V stacks; cleanse worth is a status fact, its use a spell-side term list); Fable (the LoadUse shape, tentative)
supersedes: [0060, 0061]
superseded-by: null
revisit-when: "A use needs to read another concept's load or the whole bag at once (a cross-concept use), which a per-concept spend cannot see; or the int default_face tag on StatusDef grows past a two-way map"
sources:
  - "#1727"
  - "#1591"
  - "docs/adr/0060-infusion-vocabulary-aspect-intake-int-ratio-affinity-times-ingest.md"
  - "docs/adr/0061-a-hits-explosive-load-resolves-through-the-intake-rows-face-and-a-blast-replicates-the-hit.md"
  - "docs/domain/aspect-cell-authoring.md"
  - "attack/spell/load_use/load_use.gd"
  - "attack/spell/aspect_intake.gd"
tags: [spells, infusion, status, architecture]
---

# ADR 0070 — An intake row's load use is a swappable resource

## Context

ADR 0060 fixed the load arithmetic (`innate + floor(infusion × ingest × affinity)`, int:int) and said `Infusion.riders` emits one `ApplyStatusEffect` per concept. ADR 0061 then gave each `AspectIntake` a `face` enum (INHERIT / DETONATE / PLANT / FUEL), read by if-chains in `Infusion.riders`, `Infusion.detonate_load` and the row's tooltip; ADR 0062 put the INHERIT default on the `StatusDef` as an int tag. Absolution (#1591) needs a fifth behaviour, cleanse, plus spell-level pieces (a price term list) that an enum value has nowhere to hold.

## Decision drivers

- **Open set:** a new way to spend load is a new class, not a branch in three places.
- **Owned data:** a field that only one behaviour reads (`stack_terms`, `power_from`) lives on that behaviour.
- **Module deps:** `effects/` may not name `attack/`, so the status's default stays a plain tag.
- **Behaviour identical:** riders, blast load and Firecracker's fuel are unchanged.

## Decision

Owner, 2026-10-20, on #1591: *"Spells don't list their riders, they just got a dict, load, of aspect:value pairs. The spell decides how it uses any of it. Default behaviour for load of aspect A valued V is to apply V stacks of A's related status effect ... sounds like one resource being swapped out for another ... Idk let Fable find the right shape for this"*.

Owner, 2026-10-20, on #1591 (pricing a cleanse): *"this spell might cost health, others might do it for free, or might have different price configuration ... what would be the best shape for all this?"*, then *"Move it now"* on the pass's answer: what a stack is **worth** is a status fact; what a spell **does** with the stacks it cleared is a spell-side list of terms.

Fable's pick (tentative, revisable), as built:

1. `AspectIntake.use: LoadUse` (null = inherit). `LoadUse` is an abstract `@tool` Resource: `spend(row, status, amount, bag)` contributes to a per-cast `LoadBag{riders, detonate_load}`; `describe(row, board, read_node)` is the row's tooltip line.
2. `PlantUse` owns `stack_terms` and `power_from` and emits the `ApplyStatusEffect` at `power = load`; `DetonateUse` adds to `detonate_load`; `FuelUse` spends nothing (a spread reads `PropagationContext.load`).
3. `AspectIntake.use_for_status` is the one place `StatusDef.default_face` (1 = detonate, else plant) maps to shared default instances; a row-less infused concept resolves through it too.
4. `Infusion.bag` is one walk over `load_of`; `riders` and `detonate_load` read it.

## Consequences

- A cleanse (or any later use) is one subclass and one sub-resource on a row; nothing in `Infusion` changes.
- A FUEL row describes itself as fuel, not as "Applies N Explosive".
- Every `.tres` that authored `face`, `stack_terms` or `power_from` on a row carries a `use` sub-resource instead.
- 0060's load arithmetic and vocabulary stand; only its rider sentence is retired. 0062's default-on-the-status stands.

## Alternatives considered

### A `CLEANSE` value on the `Face` enum
Lost on *open set* and *owned data*: a fifth if-branch in each reader, and the cleanse's price terms would hang off every row. Most likely revived only if uses stay a closed, data-free set.

### A use that sees the whole bag
Not needed yet — every shipped use is per concept. The `revisit-when` names the trigger.
