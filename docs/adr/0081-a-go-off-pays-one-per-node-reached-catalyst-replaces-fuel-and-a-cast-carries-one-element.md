---
id: 0081
title: A go-off pays 1 stack per node it reaches and may dig under T; a Frozen node shatters on a blade's touch, any crit, or a flat damage threshold, bursting as %-max-HP TRUE damage ∝ the excess; Frozen mutes Shocked until the break releases it; a holder's death leaves terrain alone; Fuel leaves Fire and is Catalyst, an element-generic aspect that converts its whole store 1:1 into the one element a hit lands; a cast carries at most one element, orthogonal to its subtype, and the element count is ranged's access — supersedes 0072 §3 and 0075 §6 in part
status: accepted
date: 2026-11-09
deciders: owner (go-off cost and dig, shatter shape, breakers, frozen solid, death, Catalyst and its trade, one element per cast, the orthogonal axis, the count as access, the Ice pricing lean); pass (power read post-land, Catalyst's cap, colouring on prime, the world-turn scope line — tentative)
supersedes: [0072, 0075]
superseded-by: null
revisit-when: "a hit needs to carry more than one element (the slice trade returns), a Frozen burst at deep freeze proves too swingy for the flat breaker, or the world-turn settle grows a roll"
sources: ["#1716", "#1765", "#1444", "#1660", "#1733", "docs/design/elements.md", "docs/handoffs/fuel-to-catalyst-arc.md", "docs/adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md", "docs/adr/0072-an-aspect-is-one-status-an-element-is-a-status-family.md", "docs/domain/multiplayer-sync-model.md"]
tags: [combat, on-hit, elements, status, reach, infusion, aspects, determinism, architecture]
---

# ADR 0081 — A go-off pays per node reached; Catalyst replaces Fuel; a cast carries one element

## Context
ADR 0075 (2026-11-08) made reach terrain-only and left open what a go-off pays, how a shatter turns excess into damage, Ice concentrate's shape, and how many elements a cast carries; its §6 kept Fuel as Fire's accelerant, and ADR 0072 §3 had made Fire wholly an element with no Explosive aspect surviving. Fuel was then the one inert buildup with no Ice or Lightning counterpart, filed under Fire only because it fed blasts. #1765 asked how ranged gets element arrows as easily as melee gets a Clamp. The attack record (ADR 0077) is post-apply and ADR 0079 says only `OutcomeApplier` mutates the world, while the terrain settle also runs on the world turn with no command behind it. Nothing elemental is built; the cost was docs.

## Decision drivers
- **One law across the triad:** one cost rule, one breaker set, one bar shape for Fire, Ice and Lightning.
- **Terrain is owner-blind:** no rule may read who holds a node; death is not a hit.
- **One supply per thing:** a converter in no family needs no per-element twin and no second count.
- **A hit carries 0 or 1 element**, so every conversion is whole, never sliced.
- **Deterministic, roll-free world turn:** what time does is reproduced by every peer, never recorded.

## Decision
1. **A go-off pays 1 stack per node its reach touches** — Shocked per neighbour struck, Burning per disc node, Frozen inward: one target, the whole store (owner, 2026-11-08: *"charge is more travel-across-edges-ey"*; *"at some explosion size, fire would hit basically "all its nbs" like equalling a shock to each nb"*). A blast whose disc reaches no other node does not go off (*"possibly extend this rule to make it cost 0 if it hits nobody?"*; *"there should be at least 1 stack disappearing, possibly more"*). A spend pays in full even under T (*"would decharge more rapidly"*). Pass pick: power is the excess read after the triggering hit's riders land; primed-ness reads pre-hit.
2. **The shatter is corruption-shaped**: it removes everything above T, overflow included, and deals excess × a knob fraction × max HP as TRUE damage through the shared burst path, nothing if unallocated (owner, 2026-11-08: *"frozen side: effect removed at %maxhp propto the amount removed"*; *"drop crit for now. might do something else with it later"*). A blade vertex on Frozen pops that one vertex and breaks the ice (*"We want to pop just the two vtx. Not too dramatic, and remember Ice is 0D. Point like. Single target. So no splash or anything just a fragile snap"*).
3. **Ice breaks on a blade vertex's touch, any crit hit, or any damage at or above a flat threshold**, direct hits and arriving copies alike (owner, 2026-11-08: *"a flat amount not scaling with excess. else it would mean that a deep-frozen node would require more damage to shatter right? and that doesn't sound good"*).
4. **Frozen mutes the node's own go-offs; the breaking hit releases them in the same settle** — one compound read, never a re-evaluation (owner, 2026-11-08: *frozen solid*, then *trapped until broken*).
5. **A holder's death changes nothing** on terrain (owner, 2026-11-08, picked *terrain persists* over a terrain hit per primed node).
6. **Fuel leaves Fire and is Catalyst**, one side-less terrain status in no family, the Explosive aspect retagged (DEX): inert, never counting toward T, it converts its whole store 1:1 into the element a hit lands on its node, or into the element whose stack primes the node (owner, 2026-11-09: *"maybe we should move Fuel OUT of Fire, and turn it into smth like "Catalyst" instead, and let it act on any incoming elemental-terrain status (Heat, Cold, Charge)"*; *"like "3 Catalyst" has incoming hit of "2 Heat" and it turns it into "5 Heat" doing a 1:1 Catalyst→{incoming element} trade"*; *"yeahhh exactly option 1. w/visually like purple crystals or smth instead of black goo"*; on the trade: *"iff we decide a hit can have at 0 or 1 Element associated with it then we don't need the "slice" part and can just consume all"*). Greed does not multiply element stacks (*"i think Greed shouldn't multiply incoming Heat/Cold/Charge stacks, but Catalyst may?"*). Pass picks: Catalyst caps at the same k × T; colouring on prime is read at settle.
7. **A spell carries at most one element; the forge adds to it or swaps it for the cast** (owner, 2026-11-09: *"the spell should carry at most one Element (fire/cold/lightning) and if a spell already has one, forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"*). **The element is an axis orthogonal to the subtype** (*"what if the element of each arrow is orthogonal to its subtype? (where subtype often just adds riders for e.g. aspects status stacks?) explore this concept"*), generalised by the pass to casts and blades. **The count is ranged's access**: fire ≥ 1 mints element-tagged arrows per reload (owner, 2026-11-09, picked over a temp quiver addon and a starter ammo type).
8. **Ice concentrate prices by an authored per-hop multiplier** on the Ice row's int:int affinity (owner, 2026-11-08: *"leaning 1"*); the forge's elemental slot is one element field, three int:int units (*"spells could use a separate elemental affinity (3 units of int:int, for fire/ice/lightning …)"*).
9. **Two clocks, two sync shapes** (pass, 2026-11-09, stated to the owner, not objected to): the attack record carries what a command did, go-offs included; the world turn carries what time did — decay, diffusion, Burning's burn, a no-parent go-off — reproduced by every peer from the end-turn command as DoT ticks are today. ADR 0079's "mutated only by `OutcomeApplier`" is scoped to attack resolution; the determinism obligation widens from the stat pipeline to the stat pipeline plus the world-turn settle, which stays roll-free.

**Falls:** 0072 §3's *"no Explosive aspect survives"* and *"Fuel is Fire's medium"* (its rejected *Explosive kept beside Fire* ground — two counts feeding one family — is dead: Catalyst is in no family); 0075 §6 (Fuel the accelerant, N Heat per Fuel). **Stands:** everything else in 0072 and 0075.

## Consequences
- One cost law: a leaf's cheap prime and a hub's dear one scale by the same rule; a capped hub pays out as a volley (20 → 10 → 5 → 3 → 1 on degree 5); a tiny fire cannot be beaten out by hitting it — Cold and decay extinguish.
- Deep freeze raises the burst's stakes, never the wall's strength; a frozen wire is a visible bomb.
- One converter serves three elements; the Explosive artifacts retag instead of dying; a goo arrow is budgeted by `catalyst_aspect` as a poison arrow is by its count, so the Clamp-parity ask is answered for kegs and the count for element arrows.
- The forge gains an element field per cast, not slots; `Infusion.load_of` collisions stay possible only on arrows, addons and a spell wanting two rows of one family.
- The world turn carries a reproduced settle with no record: any roll added to it later would break every peer.

## Alternatives considered
### One stack per blast, a radiating transfer of stacks to the reached nodes, or a spend clamped at T
Lost on *one law*: a big disc underpays a shock, the transfer mirrors diffusion, and the owner picked dig-below-T (2026-11-08). Dead.
### A breaker scaled by the excess; the shatter's crit side
Lost on *one law*: a deep-frozen node would be harder to break. The crit side is parked by the owner (*"might do something else with it later"*) — **most likely to be revived**.
### Shocked firing through Frozen; a terrain hit per primed node on the holder's death
The first lost to *frozen solid*: the ice wins, the Charge is trapped until the break. The second lost on *terrain is owner-blind*. Both dead.
### Fuel as Fire's second form, the keg subtype, or per-element buildups (ice-fuel, lightning-fuel)
Lost on *one supply per thing*; owner, 2026-11-09: *"either this, OR we add an "inert fuel-like buildup" status for Ice and Lightning too so each has one of them. but i think that'd just be a less comprehensible, more tedious and less fluent way to go about this"*; the keg is *"very much linked to AoE hence in that sense very "fiery""*. Dead.
### Catalyst as its own count, or found-only terrain; a sliced Greed-like trade
Lost on *one supply per thing* and *a hit carries 0 or 1 element*. The slice returns only if hits carry several elements — the `revisit-when`.
### A temp quiver addon or a starter ammo type for element arrows
Lost on *one supply per thing*: a resource that does not exist yet, or two sources of one supply. Dead.
### Recording the world-turn settle in the attack record
Lost on *deterministic world turn*: no command owns it, and DoT ticks already land unrecorded. Dead while the settle is roll-free.
