---
id: 0097
title: Conduction is cut — a spell walk spends hops on a Shocked node like anywhere else; every Fire and Lightning go-off voids a floor of 1, always, and pays 1 more per node it reaches, moved onto that node by default, so Fire's disc now spreads Heat; the floor is one additive knob on the base `GoOff`, and a Burning disc that reaches nobody still pays it (tentative) — supersedes 0081 §1 and 0084 §7 in part, and reverses the 2026-11-10 conduction lean
status: accepted
date: 2026-11-20
deciders: owner (cut conduction, the void floor, one pay rule of floor + 1 per node reached moved); pass (the floor as one additive knob on the base `GoOff`, an empty reach still paying the floor — tentative)
supersedes: [0081, 0084]
superseded-by: null
revisit-when: "a graph-wide count of Heat / Charge in play shows production outrunning void + decay (void more, or void in addition to moving — the owner's own knobs), a Burning node whose disc reaches nobody paying its floor reads wrong in play, or one shared floor needs to split per element"
sources: ["#1838", "#1839", "docs/handoffs/owner-forks-2026-11-18.md", "docs/design/elements/go-offs.md", "docs/design/elements/terrain.md", "docs/domain/elements.md", "elements/disc_go_off.gd", "elements/edge_go_off.gd", "attack/outcome/hit_gather.gd", "attack/spell/spell_resolver.gd", "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md", "docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md", "docs/adr/0093-at-the-ice-a-merged-landing-is-one-arrival-a-thawing-absorbed-copy-walks-on-and-the-trapped-go-off-releases-once-per-breaking-hit.md"]
tags: [combat, on-hit, elements, status, reach, spells, balance, architecture]
---

# ADR 0097 — Conduction is cut; every go-off voids a floor of 1 and moves 1 per node it reaches

## Context
As built, a Shocked node's arc pays 1 Charge per node reached and moves it there (0084 §7, `spent_charge_goes_to` = Reached node), so an arc voids nothing and only decay removes Charge; Fire's disc pays 1 Heat per node reached and voids it (0084 §7: *"Burning and Frozen keep the void"*), with `DiscGoOff.solo_cost_floor` 1 applied as max(floor, spent) and a disc reaching nobody no go-off at all (0081 §1, `elements/disc_go_off.gd:15`, `:110`). On top of the cascade, a spell's projectile landing on a Shocked node conducted: the walk left without spending a hop, even at 0 hops, for 1 Charge voided (`attack/outcome/hit_gather.gd:372-379`, `conduct_cost` 1) — kept on the owner's 2026-11-10 lean (*"i forgot i designed that as a feature. it's rather powerful, not spending a hop. but might be just what it needs"*, then *"i agree with that lean."*, `docs/design/elements/go-offs.md:208-210`). On 2026-11-20 the owner reopened both. Blade vertex spend was asked in the same talk and left open.

## Decision drivers
- **Things can settle:** a world of primed nodes must drain by something other than decay alone. On a wire of four (X–A–B–C–D–Y, degree 2, T 4, A–D at Charge 6) one hit cascades A → D and 22 of the 24 Charge stays on the wire, none voided, every node still Shocked; conduction then re-runs the whole cascade once per wave of the walk (`docs/handoffs/owner-forks-2026-11-18.md` § Next session starts here).
- **Lightning's line is the arc** (owner, 2026-11-06: *"elec - hops -> 1D (lines)"*): one line-maker, not a cascade doubled by a free walk.
- **One pay rule for Fire and Lightning**, so their graph-wide buildups can be compared and balanced.
- **Spread over hoard:** moving the paid stacks spreads decay over more nodes and slows re-priming the node that went off.
- **Void and move are balance knobs**, not element identities.

## Decision
1. **Cut conduction.** The owner picked *Cut it* (2026-11-20): the arc is Lightning's only line-maker; a spell still sends its payload down a wire through the arcs, but its walk spends hops there like anywhere else (owner, 2026-11-20: *"i'm kinda wondering whether conduction should be kept, or that it makes it all too doubled-up strong. [...] do we ALSO need to let spells walk on through them at no cost?"*). This reverses the 2026-11-10 lean; `conduct_cost` and every conducted-walk term go.
2. **Every go-off voids a floor, always** (owner, 2026-11-20: *"so for payment when goes off, i'd say: * void AT LEAST 1, always. it's the condition that things can settle at all"*).
3. **Fire and Lightning pay floor + 1 per node reached; the per-reached part moves to the reached node by default, for both** (owner, 2026-11-20: *"fire pays 1 (floor) + 1 per node reached."*; *"voiding at least 1 is a measure to enforce settlement in the long run, transferring (or voiding) any besides that is there to: 1) spread things around. lightning/fire transferring 1 heat /lightningto nodes it touched with an arc/explosion sounds logical right?"*; *"at least that's how i see these void/transfer concepts: knobs to tweak spread and feel and decay etc"*). Where the per-reached part goes stays each element's `spent_*_goes_to` knob; Fire's default changes from void to Reached node.
4. **Pass pick, tentative: the floor is one knob on the base `GoOff`**, default 1, added to the per-reached spend — never today's max(floor, spent).
5. **Pass pick, tentative: an empty reach still pays the floor.** An arc always reaches someone; a Burning disc can reach nobody, and its node, when hit, still voids its floor (a bool knob, default on, read from the owner's *"always"*). Only that payment changes; whatever else "no go-off" does stays as built.
6. **A blade vertex keeps its current rule until the blade-vertex spend issue settles.** Frozen's shatter (0081 §1, *inward: one target, the whole store*) is untouched.

**Falls:** 0084 §7's *"Burning and Frozen keep the void"* for Burning; 0081 §1's void of a disc's spend and *"A blast whose disc reaches no other node does not go off"* as a payment rule; 0084's *"the conduct cost"* as a wire's end. **Stands:** 0081 §1's 1-per-node cost law and dig-below-T, 0084 §7's arc transfer and shape-blind reach, 0084 §4's solo cost (now floor-inclusive), 0093 §5's arc paying only for the nodes it reaches.

## Consequences
- The wire of four now drains: each set-off voids 1, so one hit voids 4 of 24 and leaves A and D at T 4, no longer Shocked; no wave re-runs the cascade for free.
- Owner's arithmetic (2026-11-20): a degree-D Burning or Shocked node with N stacks reaching all D neighbours ends at N − D − 1 and each neighbour gains 1, so the next decay tick removes 1 + D instead of 1, and the node re-primes slower.
- Fire spreads: more Heat stays in play than under the void, on top of world-turn diffusion — the global counts now rest on the floor, the void/move knobs and decay, unmeasured.
- A spell crossing a wire pays hops; Lightning's chains come from arcs alone, and the conduction code, its `.tres` field and its test leave.

## Alternatives considered
### Keep conduction, as built
Lost on *Lightning's line is the arc* and *things can settle*: the free walk doubles a cascade the arcs already deliver. The owner's 2026-11-10 lean was its ground; reversed by the owner, dead.
### Either, not both — a Shocked target either goes off or conducts the walk
Lost on *one line-maker*: keeps the doubling's shape and adds a second rule to decide which happens. **Most likely to be revived** if a wire must carry anyone's magic again.
### Floor of 1, elements keep their verbs (Fire voids per node); or both void
Lost on *spread over hoard* and the owner's *"fire pays 1 (floor) + 1 per node reached"*. Not dead as values: Void stays each element's knob setting, the owner's lever if production runs high.
### The floor as max(floor, spent) (today's Fire), or a per-element floor
Lost on the owner's N − D − 1 arithmetic, which is additive; a per-element floor lost on *one pay rule*. The max form is dead.
### A disc reaching nobody pays nothing (0081 §1)
Lost on the owner's *"always"* (pass reading) — the `revisit-when`. 0081's rejected *radiating transfer* ground (*"the transfer mirrors diffusion"*) is dead: spreading is now the stated reason to move.
