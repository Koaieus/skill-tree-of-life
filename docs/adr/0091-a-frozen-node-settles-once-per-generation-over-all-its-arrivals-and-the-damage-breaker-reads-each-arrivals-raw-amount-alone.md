---
id: 0091
title: Within a beat a Frozen node settles once per generation over all its arrivals — if any arrival breaks it, it shatters once and every path through it walks on, only the breaker(s) taking the break's extra landings; the shatter is read in stage one with the go-offs; the damage breaker reads each arrival's raw amount as thrown (crit in, × its load, no armor or floor), tested alone — fills 0087's same-beat double break and makes 0083 §5's one snapshot per beat generational at the ice
status: accepted
date: 2026-11-11
deciders: owner (the node settles first, the shatter read in stage one, the raw damage as thrown, each arrival tested alone); pass (a multi-hop arc advancing one hop per generation, the shatter as the 0D go-off — tentative)
supersedes: [0087, 0083]
superseded-by: null
revisit-when: "an arc stopping at or passing a Frozen node a generation 'late' reads wrong in play, or testing each arrival alone makes ice too hard against swarms of weak hits; the pass readings (one hop per generation for a multi-hop arc, the shatter as a point GoOff on the Element def) reopen if Lightning's or Ice's spec reads them otherwise"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0087-terrain-lands-at-the-tip-of-every-hit-and-a-shatter-no-longer-ends-the-walk.md"
  - "docs/adr/0083-a-hit-lands-its-terrain-riders-first-then-primed-ness-and-power-are-read-from-the-result.md"
  - "docs/adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md"
  - "docs/adr/0090-a-break-of-frozen-counts-as-2-channels-and-every-blade-contact-lands-weight-decides-only-the-break.md"
  - "attack/outcome/crit_roll.gd"
  - "attack/formulas/mitigation.gd"
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0091 — A Frozen node settles once per generation; the damage breaker reads each arrival's raw amount

## Context
ADR 0087 §3 (2026-11-10) let an arrival that breaks the ice walk on, and its `revisit-when` named the owner's worry: many hits of one beat meeting at the ice. ADR 0083 §5 had same-beat hits start from one pre-beat snapshot, and the design doc already settled a go-off's copies as the next generation; but a node one hit of the beat shatters still blocked the beat's other paths, and two breakers could shatter it twice. ADR 0081 §3 named "any damage at or above a flat threshold" (10% of the holder's max HP, a knob) a breaker without saying which number is the damage. The doc already called the shatter Frozen's match for the whole hit and the 0D go-off turned inward. Nothing elemental is built.

## Decision drivers
- **Order independence** (the owner's requirement, 2026-11-11: *"if it shatters the lightning arc either always passes through it or it never does, shouldn't be up to the in-wave hit resolution order"*).
- **A break is a pass-through** (ADR 0087 §3) holds within a beat too.
- **Stage two never changes reach** (ADR 0082): what moves a path, the target set or terrain is read in stage one.
- **A break check reads the hit's own facts:** pure, already on the hit, never recomputed, not circular.
- **One clear breaker:** the break's extra landings copy one arrival's payload.
- **No loop back from payload to terrain** within a beat.

## Decision
1. **The node settles first** (owner, 2026-11-11, picked over *Frozen for the whole beat*: *"Option 1 sounds best"*). A beat lands in generations: its own arrivals, then each go-off's copies one generation later. Within a generation every arrival at a node lands its terrain riders at once; the node is then read once over all its arrivals — primed state, Frozen, whether it breaks — and only then do paths leave it. Admission stays checked on arrival, against the node as it stood before this generation. If any arrival breaks the ice it shatters once, one burst, and every path through it walks on; only the breaking arrival(s) take the break's two extra landings (ADR 0090 §1). The answer is per generation, not per beat. Pass reading: a multi-hop arc (Shocked level 2+) advances one hop per generation.
2. **The shatter is read in stage one, with the go-offs** (owner, 2026-11-11: *"I think frozen shatters (≈go-offs) should ideally resolve in the Reach section along with other go-offs like blast or arc do"*): it moves paths, adds landings to the target set and spends terrain, so driver three compels it. Pass reading: it is Ice's 0D go-off — triggered by a breaking hit, spending everything above T, reaching only its own node at the break count, its power (the excess) sizing the burst.
3. **The damage breaker reads the raw amount, as thrown** (owner, 2026-11-11, picked over *mitigated, pre-hit*, *crit and blade only* and *actual damage after landing*): the arrival's stamped amount, crit already multiplied in (`CritRoll.apply`), × its load multiplier, against the flat threshold, before the break adds its channels. Armor and the damage floor play no part.
4. **Each arrival is tested alone** (owner, 2026-11-11, picked over *summed per generation*): weak arrivals of one generation never sum toward the threshold.

**Falls:** 0087's open "whether two same-beat hits that both break one node shatter it once"; 0083 §5's single snapshot per beat, now one per generation at the ice. **Stands:** 0087 §1–§3, a thaw not being a breaker, 0083 §1–§4 (§2's admit on arrival, now against the generation's pre-state).

## Consequences
- Every path of a generation sees one answer at the ice, whatever the order; no read loops back from payload into terrain.
- The ice can hold against a beat's direct hit and shatter when a crit arc copy reaches it a generation later, so the ported Cold spell's crit chain still breaks every Frozen node on it.
- Several breakers in one generation spend the store and burst once, each landing its own two extra payloads.
- A non-breaking sibling keeps what its admit decided and walks on through the shattered node.
- Armor never hardens ice; a swarm of weak hits breaks it only by crit or blade, never by damage.

## Alternatives considered
### Frozen for the whole beat (the owner's batch-6 lean)
Every path sees the node Frozen and the shatter commits at beat end (owner, 2026-11-11: *"Perhaps a frozen node remains frozen for all during the hit after all, shattering as a result of combined hits, and none of these hits pass through it.. maybe. Not sure"*). Lost on *a break is a pass-through*: it takes back 0087 §3 within a beat, the owner's own example resolves to "never passes", and the ported Cold spell's chain stops at its first Frozen node. **Most likely to be revived** if generation-late passing reads wrong in play.
### Breaks settle first, as a fixed point over the whole beat
Lost on *no loop back*: the owner called it *"a spaghetti going forth between elements, terrain, riders, damage, back to elements and terrain"*, and an earlier arrival's absorption would hang on a later generation's break.
### The damage read mitigated pre-hit, crit and blade only, or actual damage after landing
Lost on *the hit's own facts*: `Mitigation.compute` on the pre-hit node lets armor protect the ice, and the hit's own Curse (raising `min_damage_taken`) lands after the read, so the number drifts. Crit and blade only drops the owner's *"a hit that deals X amount of % max health"* breaker and the Ice seed breaking on damage alone. Actual damage breaks ADR 0082 and needs a second gather.
### Summed per generation
Lost on *one clear breaker*: a summed break has no single arrival to hand the extra landings to.
