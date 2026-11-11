---
id: 0094
title: Element corrections — a node's go-off fires once per hit; Catalyst is an aspect status on allocated nodes that converts the Heat / Cold / Charge stacks landing on its node pro rata; an arrow is a subtype or an element, never both; Charge decays on the world turn; the elemental slots sit outside the spell's cap; a blade vertex pops a Frozen node only if it is still Frozen after that contact's riders — supersedes 0081, 0082, 0085, 0088 and 0090 in part
status: accepted
date: 2026-11-11
deciders: owner (once per hit, Catalyst's lifecycle and trade, the arrow rule, Charge decay, the cap, the pop read); pass (the two code facts and the 0082 wording, no owner call)
supersedes: [0081, 0082, 0085, 0088, 0090]
superseded-by: null
revisit-when: "a hit needs to carry more than one element, or Catalyst needs to act on a node its owner does not hold (the owner's own hedge)"
sources:
  - "#1816"
  - "docs/design/elements/terrain.md"
  - "docs/design/elements/hit-resolution.md"
  - "docs/design/elements/forge.md"
  - "docs/design/elements/casting.md"
  - "docs/design/elements/frozen.md"
  - "docs/design/elements/go-offs.md"
tags: [combat, on-hit, elements, status, infusion, forge, blade, architecture]
---

# ADR 0094 — Element corrections

## Context
Owner calls made after ADRs 0081-0090 left their text standing. Two facts about code are not owner calls: 0082's Context says spell shrapnel's `draws_own_crit()` is false, but `paired` is null on the code it was written against, so shrapnel rolls its own crit (the decision, a copy carries its parent's crit, is unaffected); and 0081 §9 lists a no-parent go-off under the world turn, which has no caller and is not built (`go-offs.md` § The reach rule). 0082 §1's "the hit's crit and damage facts, readable before landing" is a wording ADR 0092 §2 leaves behind: the number the ice reads is the arrival's mitigated amount, which depends on the node. Nothing here is built; #1799-#1802 build it.

## Decision drivers
- **One law across the triad**, and **a hit carries 0 or 1 element** (ADR 0081).
- **Terrain is node state; an aspect status is the holder's.**
- **Every forge point is a choice** (ADR 0085): the cap bounds the aspects.
- **One read for a vertex's pop and the path end** (ADR 0093 §2).

## Decision
1. **0081 §1: a node's own go-off fires once per hit, not once per landing entry** (owner, 2026-11-10, picked *once per hit*).
2. **0081 §5 stands for Heat / Cold / Charge, not for Catalyst**, which clears with its holder. **0081 §6: Catalyst is an aspect status on allocated nodes only**, clearing with its holder like Poison (owner, 2026-11-09: *"i think catalyst only sits on allocated nodes like most/all Aspect statuses"*, hedged: *"but we can always make an exception and make it owner-agnostic"*).
3. **0081 §6's trade (and its title, and 0082 §5's first trigger):** the whole store converts 1:1 into the Heat / Cold / Charge stacks that land on its node, however they land (a hit's or a copy's rider, an arc's transferred Charge); the hit's primary element plays no part (owner, 2026-11-11: *"catalyst should not pay attention to primary attributes and *only* consider cold heat charge stacks landing as siblings"*). Several elements split the store pro rata, largest remainder first; a tied leftover stays Catalyst (owner, 2026-11-11, picked *odd stack stays Catalyst*). *"Or into the element whose stack primes the node"* stands (owner, 2026-11-11, picked *landing + priming*). 0081's driver "every conversion is whole, never sliced" holds only when one element lands.
4. **0081 §7: an arrow is an aspect subtype or an element, never both; element arrows are their own ammo type, one per element** (owner, 2026-11-09).
5. **0081 §9: Charge decays in the world-turn pass with Heat and Cold** (owner, 2026-11-10). ADR 0079's "mutated only by `OutcomeApplier`" is restated against the settle as #1795 builds it.
6. **0085 §2 reversed: neither the shape nor the ride counts towards `SpellDef.infusion_capacity`**, which holds the aspects' points alone (owner, 2026-11-11: *"the Elemental slots dont need to count towards the cap"*). A shape or ride point is bounded by its element's count; for a spell that count is one budget shared by the shape (reach) and the ride (riders) (owner, 2026-11-11: *"for spell the budget shared between reach and riders (fire reach, Heat riders)"*). This answers 0085's rejected "free dedicated ride slot": its only cost is the element count. 0085's consequence "Adding a ride is a trade against aspect depth under one cap" goes; its revisit-when "the shape's points are settled as counting (or not)" is settled: no. 0089 §4's trim means the aspects only: one point off the last aspect-slot entry, popped at zero (owner, 2026-11-11: *"just pick the last element and reduce it, pop if empty"*).
7. **0088 §3 / §5 and 0090's "the spike pop on first contact stays":** a vertex pops a Frozen node only if it is still Frozen after that contact's terrain riders; a vertex whose Heat thaws the node lands as on an unfrozen node and survives (owner, 2026-11-11, picked *No pop: read after riders*).

**Falls:** the stale words named above. **Stands:** the rest of 0081, 0082, 0085, 0088 and 0090.

## Consequences
- Catalyst never leaves its holder alive past death; a Catalyst-only node vanishes with its owner.
- A 1-slot caster carries a ride and Poison together, and the trim never touches terrain.
- A thawing vertex is no longer a free pop.

## Alternatives considered
### The superseded readings
A go-off once per landing entry lost on *one law across the triad*; the ride counting against the cap (0085 §2) on *every forge point is a choice*; a Catalyst trade keyed to the hit's primary element, and the store split by a hit's primary rather than by landing stacks, on *a hit carries 0 or 1 element* read as landing stacks only; a Catalyst held by its node past its holder's death on *an aspect status is the holder's*, **most likely to be revived** (the owner's hedge); a pop read before the riders on *one read for the pop and the path end*.
### Catalyst over a hit with no primary: bigger rider takes all, or pro rata shaped too (not picked)
Offered 2026-11-10 (batch 4); *Bigger rider takes all* gave the whole store to the rider with more stacks (a tie to the first in forge order), *Pro rata, shaped too* split on every hit with the shape counted as one extra stack. Pro rata by landing stacks was picked and stands in §3.
### Batch 4 for 0089
Offered to the owner in #1814's batch 4 (2026-11-11, 00:47) for 0089 and not picked, listed here because 0089's body is not edited; no ground beyond what the owner gave.
### Overclock display: tally only, or glow the casters (not picked)
*Tally only*: the forge tally reads "base (+N)" for the best caster, and the real cap of the picked target; no marks on the board. *Glow the casters*: casters with spare degree glow with their bonus while targeting. The owner picked *pip on targets*.
### A low-cap pick: keep it, block the cast (not picked)
The pick stands, the overrun shows red and the cast cannot be confirmed until points are removed. The owner picked *trim to its cap*.
### AI fill: a fraction per tier, or the full source cap every tier (not picked)
*Fill fraction per tier*: each tier fills a fraction of its source's cap (BRAWLER 50% to WARLORD 100%); amends the ladder's no-weighting rule. *Fill to cap, every tier*: difficulty-shaped spending filed as a follow-up. The owner picked *overclock is a habit*.
