---
id: 0082
title: A hit resolves in two stages — terrain first (at each node, primed states read pre-hit, element riders land, power read post-land, go-offs spend and name the nodes they reach, cascades included) until the whole target set is gathered, then payload (other riders, then damage) lands once per gathered entry at its share; a Frozen node absorbs an under-threshold copy whole; a go-off copy carries its parent's crit; Catalyst colours on a hit or on priming — supersedes 0074 §1 in part, refines 0075 §4–5 and 0081 §1
status: accepted
date: 2026-11-09
deciders: owner (two stages, absorption, copy crit, Catalyst's two triggers); pass (primed-ness and the Frozen check kept pre-hit at every node)
supersedes: [0074]
superseded-by: null
revisit-when: "an aspect rider ever needs to change reach (it would have to land in stage one), or a node reached twice should take one landing rather than one per entry"
sources: ["#1716", "#1733", "#1741", "docs/design/elements.md", "docs/adr/0074-a-hit-lands-in-three-phases-cold-absorbs-reach-frozen-is-a-glass-ceiling.md", "docs/adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md", "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md", "attack/spell/on_hit/", "docs/domain/attack-timeline.md"]
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0082 — A hit resolves in two stages: terrain gathers the target set, then payload lands per target

## Context
ADR 0074 §1 (2026-11-05) had each landing run read / land / settle and emit copies that recurse, so a hit's target set was known only when the recursion ended, while the attack record (ADR 0077) already carries a blast as one mark and its copies. ADR 0081 §1 recorded power read post-land as a pass pick. Three rules a drone would have to guess at were still open in the design doc: what a Frozen node does to a copy under its break threshold, whether a go-off's copy inherits the trigger's crit (a melee blast's copies and riding landings do today, a spell blast's shrapnel does not — `PairedDamageInstance.draws_own_crit()` is false), and whether Catalyst converts when its node primes by flow or only when a hit lands. Nothing elemental is built.

## Decision drivers
- **One gather, one list:** the target set exists before any damage lands, so the record, the dual-reach dedupe knob and the reveal read a list, not a tree.
- **Terrain resolves as terrain:** every stack mutation, spend and conversion sits in one stage; the payload stage never touches a stack.
- **No re-evaluation:** a hit's crit and damage are its own facts, readable before landing; every primed-state read is pre-hit.
- **LET IT RIDE:** a copy carries everything its hit carries (ADR 0075 §5), the crit included.

## Decision
Owner, 2026-11-09: *"resolve elements first which settles the reach [as in, total set of targets] for the hit (including cascades..?) and then resolve the remainder of the hit for each target (riders, damage?)"*, confirmed as the two stages below with the pass's pre-hit refinement.

1. **Stage one, terrain.** At the node a hit lands on: read its primed states as they were before this hit (the reach; the Frozen check is here, against the hit's crit and damage facts); land the element riders, Catalyst converting as they add; settle — Heat × Cold netting, power read post-land, the go-offs the read found spend their stacks and name the nodes they reach. Each reached node runs the same steps on the copy's element riders, under the once-per-node-per-hit cap; dual reaches concatenate. The result is the whole target set with a share per entry — the record's blast table — before anything else lands. ADR 0081 §1's post-land power is a consequence of this order, no longer a pick.
2. **Stage two, payload.** For every gathered entry the other status riders, then the damage, land at that entry's share; the shipped order inside a landing stands (ADR 0067, #1741). A node present twice takes one landing per entry.
3. **A Frozen node absorbs an under-threshold copy whole** — no damage, no riders, the path ends; a copy that breaks the ice lands; a direct hit lands either way (owner, 2026-11-09, picked *absorbed* over *lands, then stops*). Only a direct Cold hit deepens a freeze.
4. **A go-off copy carries its parent's crit** (owner, 2026-11-09, picked *it rides* over flat copies); spell shrapnel comes to copy the hit's crit as a melee blast's copies already do.
5. **Catalyst converts on two triggers** (owner, 2026-11-09, picked *hits and priming*): a hit carrying one element lands on its node, or the node primes by any route, read at settle.

**Falls:** 0074 §1's per-landing recursion. **Stands:** its read / land / settle as the steps of stage one at each node, and 0075 §4–5 as refined.

## Consequences
- The attack record's blast table is produced by stage one as is; the dedupe knob is one switch at the gather; the reveal can show the reach before the hits.
- An aspect rider can never change reach, since it lands only in stage two; a Heat arrow's own Heat joins the blast it triggers (the ramp).
- A 3-Cold leaf shrugs off AoE splash entirely, paid for by brittle, cold passage and its holder's own walks stopping there.
- Spell shrapnel gains the hit's crit: blasts get swingier by exactly the crit multiplier, once per hit.

## Alternatives considered
### Per-landing recursion (0074 §1)
Lost on *one gather, one list*: same results, target set known only at the end. Dead.
### Power read on the pre-hit snapshot
Lost on the owner's ramp (*"heat builds up as arrows land, critical at some point, then explodes"*): a Heat arrow would never feed the blast it triggers. Dead.
### Frozen as anti-reach only (the copy lands, then stops)
Lost on the doc's wall reading, *"a copy that breaks through also lands"*: Frozen is a boon with named costs, not a travel rule. **Most likely to be revived** if a cheap leaf freeze proves too strong.
### No crit on any copy
Lost on *LET IT RIDE*. Dead.
### Catalyst colouring on hits only
Lost on element symmetry (owner: *"still element-symmetric right?"*); only temperature primes without a hit in practice. Dead.
