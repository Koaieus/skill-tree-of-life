---
id: 0047
title: Infusion is a per-cast fifth spell component — INT-derived slots, spell-side ingest rates, and an innate affinity that replaces authored status riders
status: accepted
date: 2026-10-07
deciders: owner (slots capped by INT, the spell dictates ingest with an innate element list, migrating the four template spells, DX); pass (one in-rate per aspect, the field names, `SpellAffinity` pointing at the `StatusDef`, Hex status-only and the relaxed `validate`)
supersedes: []
superseded-by: null
revisit-when: "A spell needs an out-side multiplier its `rate` and the status's `stacks_per_hit` fold cannot express, or a per-spell infusion tax (power dilution, −hops) is wanted"
sources:
  - "#1250"
  - "#1461"
  - "#1462"
  - "docs/domain/aspect-cell-authoring.md § Infusion"
tags: [spells, aspects, status, infusion, architecture]
---

# ADR 0047 — Infusion is a per-cast fifth spell component

## Context

A status spell (Venom, Hex, Dazzle, Sunder) authored its stacks as an `ApplyStatusEffect(def, power)` in `on_hit_effects`. The four spells differed only in that number. The magic column of the aspect matrix needed a way for the caster to spend `<concept>_aspect` on a cast. `docs/domain/aspect-cell-authoring.md` § Infusion held a provisional reading: an `Infusion` resource with an on-hit effect and a drawback, scaled by charges. The 10-03 gist had already settled that riders are `OnHitEffect`s and that a dual infusion is two riders per landing.

## Decision

Owner, 2026-10-07, on #1250, verbatim:

- *"if magic would also get a limiting factor of how much infusion they can really do, i think that would close the ranks … like maybe an INT-dependent max amount of infusions for a spell. e.g. 'oh you got just 50 INT, that's gonna give you 1 infusion slot to fill with any 1 aspect budget currency you got'"*
- *"the spell can dictate entirely how it uses the infusion it's been given. possibly innately has an infusion by default -- like an element list. … say venom has innate 5 poison and accepts extra infusions 1:1. then adding 3 poison makes it 8. 8 poison stacks a piece. say cyclone has innate 0 poison and a 1:2 rate of ingesting infusions. adding 1 -> does nothing. adding 2N -> adds N … maybe venom even has a 2:1 rate for accepting poison infusions? … and maybe it would still use 1:1 for the other aspects, or maybe even `0:*` for others -- disabling them entirely."*
- *"so i'd say option 1 here"* — the four template spells migrate to an innate count, so spell stacks have one path.
- *"anything we decide on also needs to be accompanied by perfect DX -- excellent editor feedback and Inspector-editability"*

So:

1. **`SpellDef.affinities: Array[SpellAffinity]`** is the spell's element list. Each entry has a `status` (the concept's `StatusDef`), `innate` points, and an ingest `rate`. `SpellDef.default_rate` covers concepts the list leaves out. A rate of 0 refuses a concept.
2. **`Infusion`** (`attack/spell/infusion.gd`) is the per-cast component. `affinity_of(spell)` returns `{concept id: innate + floor(points × rate)}`. `riders(spell)` returns one `ApplyStatusEffect(def = status, power = affinity)` per concept whose affinity is above 0. `SpellResolver.resolve_against(…, infusion = null)` runs those riders after `spell.on_hit_effects` at every landing. A null infusion means `Infusion.innate(spell)`, which is the spell as authored.
3. **What lands is `affinity` stacks per hit**, through the status's own `stacks_per_hit` fold. The tooltip line (`SpellAffinity.get_description`) calls the same fold, so the readout and the landing agree.
4. **No `SpellDef` authors an `ApplyStatusEffect`.** It stays the rider that arrows and blades author, and the thing `Infusion` emits.
5. **Slots come from INT; supply comes from `<concept>_aspect`.** An `infusion_slots` stat sets how many concepts a cast may infuse. The caster's `<concept>_aspect` caps the points in each slot. Nothing is consumed. The points, the slots stat and the wire are #1462.

Pass calls (Claude, 2026-10-07, revisable):

- **One rate per concept, on the in side.** The out side is the status's `stacks_per_hit` fold. The owner's sentence allows a second out-rate. One knob covers the "many small vs few big" axis.
- **`SpellAffinity.status: StatusDef`, not `Aspect`.** `Aspect.spells` already points at the spell. `aspects/aspect.gd` states the rule: *"Facets point at the Identity, never at the Aspect — this resource is the only edge from a concept to its facets, so there is no cycle."* The concept id is `status.identity.id`.
- **Hex is status-only.** It never authored a `DamageEffect`. `SpellDef.validate` therefore refuses a spell only when both `on_hit_effects` and `affinities` are empty.

## Consequences

- To add a status spell, author a `SpellAffinity`. No new effect class and no per-spell stack field.
- The tooltip's "Applies X (N per hit; +r per x infused)" line comes from the affinity. The rate is visible in the Inspector and in the tooltip.
- `test_aspect_roster.gd` pins that every spell an `Aspect` lists carries an affinity for that concept.
- A concept with no status (explosive) cannot be infused until its own face lands.

## Alternatives considered

- **An `Infusion` resource authored on the spell (effect + drawback, on/off)** — the provisional reading. Dead: the owner wants per-cast spending scaled by points, and an on/off flag cannot scale.
- **Keep `ApplyStatusEffect` on the four spells and add infusion beside it** — two paths for spell stacks. Rejected by the owner ("option 1").
- **`SpellAffinity.aspect: Aspect`** — makes a `.tres` cycle through `Aspect.spells`.
- **Give Hex a `DamageEffect` so `validate` stays strict** — a design change to Hex. That call belongs to the owner, not to this plumbing.
- **A per-spell tax (power dilution, −hops)** — parked. If it is wanted, it becomes a third knob on `SpellAffinity`.
