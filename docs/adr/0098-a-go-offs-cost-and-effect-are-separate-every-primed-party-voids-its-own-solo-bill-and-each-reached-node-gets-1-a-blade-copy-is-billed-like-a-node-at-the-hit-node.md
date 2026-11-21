---
id: 0098
title: A go-off's cost and its effect are separate — every primed party voids its own solo bill (floor + 1 per node in its own reach, clamped at 0) and each node the combined reach covers gets +1 of the element's terrain once per go-off, unfunded by the cost; a blade vertex's primed copy is an incoming party resolved at the hit node and billed like a node, its source read-only, with no per-swing cap and no backlash; a cast shape alone has no effect; a copy and a shape are one `GoOffSource` on one gather path — supersedes 0097 §3's move and §6, 0084 §7's transfer and 0093 §5's transfer in part
status: accepted
date: 2026-11-21
deciders: owner (cost and effect separate, +1 per go-off over the combined reach, a shape alone has no effect, resolve at the hit node with solo bills, the source read-only, no cap, no backlash, one path); pass (a copy's floor follows `GoOff.floor_when_unreached`; mixed elements fire two go-offs — tentative)
supersedes: [0097, 0084, 0093]
superseded-by: null
revisit-when: "#1845's graph-wide Heat / Charge readout shows effect minting outrunning void + decay, or combined reach reads as too strong in play"
sources: ["#1844", "#1843", "#1845", "docs/design/elements/go-offs.md", "docs/domain/elements.md", "attack/outcome/hit_gather.gd", "attack/outcome/go_off_source.gd", "elements/go_off_result.gd", "elements/edge_go_off.gd", "elements/disc_go_off.gd", "attack/melee/sim/blade_state.gd", "docs/adr/0097-conduction-is-cut-and-every-go-off-voids-a-floor-of-1-and-moves-1-per-node-it-reaches.md", "docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md", "docs/adr/0093-at-the-ice-a-merged-landing-is-one-arrival-a-thawing-absorbed-copy-walks-on-and-the-trapped-go-off-releases-once-per-breaking-hit.md", "docs/adr/0095-catalyst-never-goes-off-and-a-blade-vertex-copies-only-a-primed-state-so-the-detonate-and-fuel-uses-the-default-face-and-the-two-sided-blade-contact-go.md"]
tags: [combat, on-hit, melee, blade, elements, status, reach, spells, balance, architecture]
---

# ADR 0098 — A go-off's cost and effect are separate; a blade copy is billed like a node at the hit node

## Context
ADR 0097 made every go-off void a floor of 1 and pay 1 per node reached, that part *moved* onto the reached node, so the stacks a node lands are the stacks its bill took; §6 left a blade vertex's primed copy (0095 §4) on its own rule. As built, the copy goes off through two private paths in `attack/outcome/hit_gather.gd` (`_fire_vertex_arc`, `_fire_vertex_disc`): it pays 1 per node reached and no floor, a Shocked copy's stacks never move, and a cast shape enters the same go-off through separate `_Hit.shape` slots and pays 0 (0084 §4). A go-off that combines two parties (0084 §3, 0093 §4) reaches past either party's own ring, and a short payer cannot fund a move per node. #1844 settled the copy over 2026-11-20 and 2026-11-21.

## Decision drivers
- **Things can settle** (0097): the cost is what stops a node instantly re-priming, so all of it leaves the world.
- **Symmetry:** no rule may need a tiebreaker between parties that players won't accept.
- **One law for a party:** a blade copy is billed like a skill node, from the node it hits.
- **A swing never writes to its source:** no cleanse-and-buff in one contact.
- **Ride plants, shape reaches** (0084 §1): terrain from a cast is the ride's job.
- **One path:** no parallel copy of the node bill.

## Decision
1. **Cost and effect are separate quantities** (owner, 2026-11-20: *"i'd rather see it not like paying but like a cost and effect separately. the cost is there to not instantly re-prime, the effect (each node reached by arc/blast) is "you get +1 charge/heat". a blast is hot. a discharge is charged. the two lv1's combining to lv2 to make more heat is effectively some catalyst amplifying the effect at a cost that could normally not be paid"*). Every primed party's cost is the floor + 1 per node in its own reach, all voided, clamped at 0 — a payer pays what it has. The effect is +1 of the element's terrain on each reached node, never funded by the cost. With a fully funded payer the totals equal 0097's void floor + move per reached.
2. **The effect is +1 per go-off over the whole combined reach** (owner, 2026-11-21, picked *"+1 per go-off"*), replacing the 2026-11-20 line that rings only the combined reach covers take payload but no Charge.
3. **A blade vertex's primed copy is resolved at the hit node and billed like a node** (owner, 2026-11-20: *"i think we could best handle this from the perspective of the hit node: a blade node comes in, primed or not, and the hit node itself also is primed or not … and is resolved/handled by the hit node."*; *"billing for blade nodes is kept similar to billing for skillnodes; billing for spell reach might.. still be 0?"*). Each primed party pays its own solo bill. The source node is read-only; there is no per-swing cap, the copy's drain is the bound (*"the blade node deosn't regain charge during the swing"*); there is no backlash. This ends 0097 §6.
4. **A cast shape alone has no effect** (owner, 2026-11-21, picked *"No, ride plants"*). The effect needs a primed party, a node or a copy; a shape alone reaches with payload only and pays 0. A shape on a primed node widens the go-off and the effect covers the combined reach.
5. **One path** (owner, 2026-11-20, picked *"One path"*): a blade copy and a cast shape are one kind of incoming party, `GoOffSource`, in the hit node's go-off; `GoOffResult` carries the node's cost, an `incoming_cost` and an `effect`; the private vertex paths die.
6. **Pass picks, tentative:** a copy that reaches nobody pays its floor as a node does (`GoOff.floor_when_unreached`); a copy of one element on a node primed in another fires two go-offs, each with its own cost and effect, summing only within one element.

**Falls:** 0097 §3's *"the per-reached part moves to the reached node"* (the effect lands instead; `spent_*_goes_to` = Void now means no effect) and §6; 0084 §7's *"each stack a Shocked go-off spends lands on the node it reached"*; 0093 §5's *"transferred"*. **Stands:** 0097 §2, §4, §5; 0084 §3 and §4 (the node's solo cost, now beside the copy's); 0093 §4; 0095 §4.

## Consequences
- A short payer still lands a full effect: a copy of 5 on a degree-8 hub goes to 0 and all 8 neighbours gain 1.
- A combined go-off mints more than it voids — owner's example, copy 10 (T 4) on a node at 8 (T 6), combined L2 over 3 + 6 nodes: 8 voided, 9 landed — the catalyst the owner described, watched only by the global counts.
- Copy alone, copy + node, shape alone and shape + node are one code path and one test table.

## Alternatives considered
### Moves capped at what was paid
Lost on *symmetry* (owner: *"has no symmetric way of going about it and needs some ugly tiebreaker that players won't accept (e.g. stable ID)"*). Dead.
### +1 per primed party (two parties give +2)
Lost to the owner's +1 per go-off pick: the combination amplifies reach, not density.
### Own ring only (the 2026-11-20 call)
Lost to the owner's 2026-11-21 pick. **Most likely to be revived** if minting outruns void + decay — the `revisit-when`.
### Shapes plant
Lost on *ride plants, shape reaches*: the shape would duplicate the ride, and magic needs AoE least.
### Paying from the source node; a per-swing cap; a backlash
Lost on *a swing never writes to its source* (owner: *"that's -1 debuff and +1 buff at the same time. might be too strong"*) and on the copy's drain as the bound. Dead.
### Patching the two vertex paths in place
Lost on *one path*: a parallel copy of the node bill.
