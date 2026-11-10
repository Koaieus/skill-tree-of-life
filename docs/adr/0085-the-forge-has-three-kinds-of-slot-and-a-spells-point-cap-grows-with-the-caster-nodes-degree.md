---
id: 0085
title: The forge has three kinds of slot — a shape field, a ride field holding at most one terrain element, and the aspect slots; the ride takes no aspect slot but its points count against the spell's total-points cap; that cap is a base plus a bonus per caster-node degree above the spell's min_degree, and a loadout gates which nodes may cast it — supersedes 0081 §7's single element field in part
status: accepted
date: 2026-11-10
deciders: owner
supersedes: [0081]
superseded-by: null
revisit-when: "the shape's points are settled as counting (or not) against the spell's total-points cap, the starting knobs (base 10, 5 per degree) leave the ride an automatic pick again, or a loadout hiding targets reads worse in play than a clamped loadout would"
sources: ["#1716", "docs/design/elements.md", "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md", "docs/adr/0060-infusion-vocabulary-aspect-intake-int-ratio-affinity-times-ingest.md", "attack/spell/spell_def.gd", "attack/targeting/spell_target_union.gd", "attack/plan/magic_attack_plan.gd", "systems/battle_system.gd", "entity/default_entity_board.tres"]
tags: [combat, elements, infusion, aspects, forge, targeting, spells, architecture]
---

# ADR 0085 — The forge has three kinds of slot; a spell's point cap grows with the caster node's degree

## Context
ADR 0081 §7 (2026-11-09) gave a cast at most one element and the forge one element field for it. On 2026-11-10 an element on a cast came to do two separate things: shape the reach (Fire's disc, Lightning's hops, Ice's shortened walk) and ride the hit as terrain stacks (Heat / Cold / Charge), so one field could no longer say which. Aspects sit in `infusion_slots`, 0–3 by INT thresholds (10 / 100 / 1000 in `entity/default_entity_board.tres`), each aspect capped by its own `<concept>_aspect` (ADR 0060). `SpellDef.infusion_capacity` (`attack/spell/spell_def.gd:135`) already caps a cast's total points and is `INF` on every spell; `SpellDef.min_degree` (`:79`) already gates which nodes may cast. `SpellTargetUnion.build` (`attack/targeting/spell_target_union.gd:125-134`) gathers the eligible sources and `_pick_best_sources` (`:209-224`) gives each target the source with the highest node-local `spell_damage`, lowest stable id on a tie; the union never sees the infusion. `MagicAttackPlan.aspect_overrun()` (`attack/plan/magic_attack_plan.gd:759-770`) is the only check of a loadout against its caps and runs at launch (`BattleSystem._can_afford`). Nothing elemental is built; the cost was docs.

## Decision drivers
- **A hit carries 0 or 1 element** (ADR 0081): the ride cannot become a second element on a hit.
- **Every forge point is a choice:** nothing at the forge may be a free default that every cast fills.
- **Terrain does not compete with aspects for a slot:** at 1–2 `infusion_slots` a rider must not be traded against Poison.
- **Existing fields, one formula:** `infusion_capacity` and `min_degree` carry the rule; no new currency.
- **The loadout is the player's:** it is never silently changed, and the source pick stays "highest `spell_damage`".

## Decision
1. **Three kinds of slot** (owner, 2026-11-10: *"one slot determines the color of the crystal in your wand {= reach}, another slot for elemental payload {at most 1}, and 'regular' slots besides that"*). ADR 0081 §7's one element field is the cast's **shape**; a second field holds the **ride**, one terrain element at most; the aspect slots stay aspects. Shape and ride may be different elements, each drawing its own count; the same element splits one count between them (owner, 2026-11-10: *"say you got 3 Fire … you can spend 1 there and 2 on Heat for 2 Heat stack riders"*). The spell's authored baseline is free on top.
2. **The ride takes no aspect slot, and its points count against the spell's total-points cap** — `SpellDef.infusion_capacity` — together with the aspects' points (owner, 2026-11-10, picked *own slot, points count against spell capacity* over a free slot, a slot paid in the hit and the rider taking an aspect slot: *"option 1, good solution"*).
3. **Overqualified casting:** a node's capacity for a spell = the spell's base cap + a bonus per degree above its `min_degree`, one formula (owner, 2026-11-10: *"if casting from a node of, say degree N, a spell has min required degree M, if N<M it cannot cast it, if N≥M it can cast, and the excess may be used for additional points e.g. 5 or so per excess degree"*). Starting knobs: base 10 (*"maybe 10 is a better starting cap"*), 5 per degree.
4. **The loadout gates the caster** (owner, 2026-11-10, picked over sorting casters by degree and over clamping the loadout to today's pick): a loadout of P points acts as a higher `min_degree`. The target union admits only sources whose capacity carries it, targets light up for those alone, and among them the pick stays the highest node-local `spell_damage`. A point added after the target is picked re-picks the source among those that can carry it, or the socket refuses the point.

**Falls:** ADR 0081 §7's *"the forge adds to it or swaps it for the cast"* as one field, and §8's *"the forge's elemental slot is one element field"*. **Stands:** everything else in 0081 — a hit still carries 0 or 1 element, the element stays orthogonal to the subtype, the count stays ranged's access.

## Consequences
- A cast may name two elements, one shaping and one riding, while every hit still lands at most one; ADR 0081's whole-store Catalyst trade is untouched.
- Adding a ride is a trade against aspect depth under one cap, not against an aspect slot, so a 1-slot caster can carry terrain and Poison together.
- `infusion_capacity` stops being inert: it is finite per spell and read per caster node, so the same loadout is legal from a hub and over cap from a leaf. `aspect_overrun()`'s total-points term therefore needs the casting node, not the spell alone.
- **The union now depends on the loadout and must rebuild whenever it changes**; before this it was a function of spell, attacker and graph only. A heavier loadout reaches fewer targets — the same reach tax `min_degree` already is — and a loadout no owned node can carry has no targets at all.
- The cap is enforced where points are socketed and where sources are gathered, not only at launch.
- High-degree nodes gain a second use beyond passing `min_degree`: degree buys points, so the strongest loadouts cast from hubs, which are also the nodes with the fewest far targets in range.

## Alternatives considered
### A free dedicated ride slot
Lost on *every forge point is a choice*: with no cost it auto-fills (owner, 2026-11-10: *"it'd be a default to also add an element … given there's no downside to adding it"*). Dead while the ride has no other price.
### A ride slot paid in the hit (a shave per stack)
Lost on *existing fields, one formula*: a second price on the damage side beside the points cap, and a rider that weakens the payload it rides on.
### The rider takes an aspect slot
Lost on *terrain does not compete with aspects for a slot*: at 1–2 slots terrain loses to Poison and the element axis goes unused for most of a run.
### Sort casters by degree first, then by damage
Lost on *the source pick stays "highest `spell_damage`"*: it would hand a light loadout to a hub that hits softer, changing every cast, not only the over-cap ones.
### Keep today's pick and clamp the loadout to that node's cap
Lost on *the loadout is the player's*: points socketed at the forge would vanish at the target. It keeps the union loadout-blind and every target lit, so it is the option **most likely to be revived** if hidden targets read badly in play.
