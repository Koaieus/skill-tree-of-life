---
id: 0095
title: Catalyst never goes off and a blade vertex copies only a primed state, so DETONATE / FUEL (`DetonateUse`, `FuelUse`, `detonate_load`), the default face on `StatusDef` and the two-sided blade contact go; `LoadUse`, `PlantUse` and `CleanseUse` stand, and a row with no use plants — supersedes 0061, 0062 and 0070 in part
status: accepted
date: 2026-11-10
deciders: owner (Catalyst inert, the vertex copies a primed state, Firecracker plants Heat); pass (which classes and fields die, PlantUse as the one default)
supersedes: [0061, 0062, 0070]
superseded-by: null
revisit-when: "a status needs to go off from a load again (a detonating aspect), or a blade vertex must carry something its node holds that is not a primed state"
sources:
  - "#1816"
  - "#1801"
  - "#1802"
  - "docs/design/elements/terrain.md"
  - "docs/design/elements/forge.md"
  - "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md"
tags: [spells, infusion, status, aspects, combat, on-hit, melee, blade, elements, architecture]
---

# ADR 0095 — The explosive load's faces and the two-sided blade go

## Context
ADRs 0061, 0062 and 0070 built an intake row's load around Explosive, the one aspect that went off: a face (DETONATE / PLANT / FUEL), its default on `StatusDef.default_face`, the `DetonateUse` / `FuelUse` uses filling `LoadBag.detonate_load`, and a blade contact that split its power into a striker's side on the board and a node's side on the blade pieces. ADR 0081 §6 retagged Explosive as Catalyst, an inert converter, and the element go-offs (Burning's disc, Shocked's arc) took over the blast. **This record takes effect as #1801 (the retag) and #1802 (the blade's explosive path) land.** At 402ac386 master still has `DetonateUse`, `FuelUse`, `detonate_load`, `StatusDef.default_face`, `AspectIntake.use_for_status` and `BladeState.vertex_charges`, and `test_blade_explosive`, `test_blade_piece_charges` and `test_explosive_charges` pin them.

## Decision drivers
- **Only an element goes off** (ADR 0081): a load that detonates is a second, parallel go-off.
- **One law for a vertex**: what a blade carries from its node is that node's state, read at fill like its stats.
- **An open use set** (ADR 0070): a new way to spend a load is a new `LoadUse` class, never an enum value.

## Decision
1. **Catalyst never goes off.** The doc's statement of the owner's call (owner, 2026-11-09: *"yeahhh exactly option 1. w/visually like purple crystals or smth instead of black goo"*; `terrain.md` § Catalyst: a converter, in no family): Catalyst is *"one aspect status, inert and colourless: it never counts toward T, never primes, never goes off and has no derived state"*. So the DETONATE face, `DetonateUse` and `LoadBag.detonate_load` / `Infusion.detonate_load` (0061 §1, 0070 §1, §2, §4) go.
2. **Firecracker's row names Fire and plants Heat** (owner, 2026-11-10, as #1801's spec records it; no verbatim in the repo). The FUEL face and `FuelUse` (0061 §1, 0070 §2) go.
3. **No default face.** With one face left, `StatusDef.default_face` and `AspectIntake.use_for_status` (0062 §1, 0070 §3) go; a row with no use plants (pass), the owner's own default: *"Default behaviour for load of aspect A valued V is to apply V stacks of A's related status effect"* (owner, 2026-10-20, quoted in 0070). Catalyst takes `PlantUse`.
4. **A blade vertex copies only its node's primed state** (owner, 2026-11-09: *"copy a burning node and you get a burning blade node (booms). copy frozen node -> frozen blade node … copy shocked node -> get shocked blade node (zaps/arcs)"*; `forge.md` § The forge). Charges are not that state, so 0062 §2 (the two sides, `power = (load + r·shared) + (present + r·shared)`) and §3 (armed, not fragile) go: a blade contact lands one hit, and a primed struck node goes off through the gather as any hit does.

**Falls:** the faces, uses, fields and the contact named above, and 0070's consequence "0062's default-on-the-status stands". **Stands:** the rest of 0061, 0062 and 0070 — among it `LoadUse` as the swappable resource on the row, `PlantUse`, `CleanseUse` and the one-walk `Infusion.bag`.

## Consequences
- An intake row's load either plants its status or does what a bespoke `LoadUse` says; nothing in the load arms a blast.
- A blade carries no charges; what it carries from its node is a primed state.
- Every blast is an element's go-off, under one spend law.

## Alternatives considered
### The superseded readings
Grounds are the pass's, not the owner's. A load that detonates (DETONATE, `DetonateUse`) lost on *only an element goes off*: no aspect detonates once Explosive is Catalyst, and a face value with no user is the closed set 0070 replaced — **most likely to be revived**, by an aspect that must go off from its own load, and then as a `LoadUse` class, not a face. The two-sided contact lost on *one law for a vertex*: a primed node already goes off through the gather on any hit, so a node's side on the blade pieces would be a second blast from the same contact.
