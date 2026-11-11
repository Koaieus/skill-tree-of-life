---
id: 0087
title: Terrain (Heat / Cold / Charge) lands at the tip of every hit, absorbed copy or not — Frozen's admit gates only damage and aspect riders, an arc's Charge commits with the spend before the admit, and an arrival that shatters the ice walks on — supersedes 0083 §2's "an absorbed copy lands no riders" and 0082 §3's "no riders" in part
status: accepted
date: 2026-11-10
deciders: owner
supersedes: [0083, 0082]
superseded-by: null
revisit-when: "a shatter that walks on proves order-dependent among the simultaneous hits of one beat (the owner's own worry), or Heat riders on absorbed copies thawing ice, or tipping a node as they hit, make Frozen too cheap to beat or the primed bands too cheap to reach"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0083-a-hit-lands-its-terrain-riders-first-then-primed-ness-and-power-are-read-from-the-result.md"
  - "docs/adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md"
  - "docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md"
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0087 — Terrain lands at the tip of every hit; a shatter no longer ends the walk

## Context
ADR 0082 §3 (2026-11-09) had a Frozen node absorb an under-threshold copy whole, "no damage, no riders, the path ends"; ADR 0083 §2 (2026-11-10) split Frozen into an admit read on arrival and a path-end and break read after the riders, and kept "an absorbed copy lands no riders" so that the node could refuse what it absorbed. That left a Cold copy unable to deepen a freeze, a Heat copy unable to thaw one, a Charge arc's transfer undefined at an absorbed node, and a hit that shattered the ice ending its walk at the node it had just opened. Nothing elemental is built.

## Decision drivers
- **Terrain is not payload:** Heat, Cold and Charge are the element's own deposit at a node, not damage or an aspect, so a gate on payload should not hold them.
- **Riders first stands:** the riders land and the node is then read (ADR 0083 §1), so a rider that tips the node has to be allowed to.
- **A spend is committed before its target is judged:** what an arc spends moves with it.
- **A break is a pass-through:** ice that has just been broken is no longer in the walk's way.
- **One snapshot per beat stands:** same-beat hits start from the pre-beat terrain (ADR 0083 §5).

## Decision
1. **Terrain lands on every arrival, absorbed or not.** Owner, 2026-11-10: *"How i see it: terrain sits at the tip of each hit, and lands no matter what. It can thaw a freeze? Or prime a node as it hits? (Or that last one might be a little intense but still kinda valid?)"* Heat / Cold / Charge riders land on every arrival; Frozen's admit gates damage and aspect riders only. A Heat rider on an absorbed copy can thaw the ice, and a rider that tips the node primes it as it hits (riders first, ADR 0083 §1).
2. **An arc's Charge commits with the spend, before the admit.** Owner, 2026-11-10: *"it resolves before right? The charge before the frozen check? Should be good so it still applies any terrain stacks (cold heat charge)"*. The transferred Charge lands even when the copy it rides is absorbed.
3. **A shatter no longer ends the walk.** Owner, 2026-11-10: *"Arrival shattering sounds like it should no longer be blocked tbh."* An arrival that breaks the ice lands and its path continues past that node.

**Falls:** ADR 0083 §2's "and an absorbed copy lands no riders" (with its driver "an absorbed copy lands nothing" and the consequence "a Cold copy onto a Frozen node lands nothing, so only a direct Cold hit deepens a freeze"); ADR 0082 §3's "no riders" and its closing "Only a direct Cold hit deepens a freeze"; ADR 0083's consequence "a hit that freezes a node ends its own walk there" for a hit that also shatters it. **Stands:** the admit read on arrival, the absorption of an under-threshold copy's damage and aspect riders, and the path-end and break read after the riders (ADR 0083 §2); 0082 §3's "the path ends" for an absorbed copy; ADR 0084 §7's arc transfer.

**Not decided here:** whether a centre copy is asked of Frozen's admit; whether an absorbed copy's path ends only if the node is still Frozen after its riders (a Heat rider that thaws it); whether two same-beat hits that both break one node shatter it once (asked of the owner, 2026-11-11). A blade touch that breaks the ice is ADR 0088 §5.

## Consequences
- A Cold copy onto a Frozen node deepens the freeze, so a splash can build the ice a direct hit used to have to; a Heat copy can thaw a node whose ice absorbed its damage.
- A rider can prime a node on an absorbed arrival, so a node that damage cannot touch can still be set off by terrain.
- An arc spends its Charge whether or not the node it reaches admits the copy, so no Charge is lost to ice.
- The walk no longer stops at a node the arrival has just broken.
- Frozen's wall is now a wall for payload alone: a deep freeze still guards a holder from damage and aspects, no longer from terrain.

## Alternatives considered
### The admit gates riders too (ADR 0083 §2)
Lost on *terrain is not payload*: a node that absorbed a copy's damage still refused its Heat, so ice could not be thawed by splash and a tipping rider could not prime past it. **Most likely to be revived** if thawing or priming on an absorbed copy proves too cheap — the owner called the priming half "a little intense".
### An arc's Charge lands only after the admit
Lost on *a spend is committed before its target is judged*: an absorbed copy would drop a Charge the arc had already paid, and the owner asked for it to apply with the other terrain stacks.
### A shatter ends the walk at the node it opens
Lost on *a break is a pass-through*: the owner wants arrival shattering unblocked. The owner's worry, many nodes hit at once in one Wave, is the reopening condition; ADR 0083 §5's one snapshot per beat is the guard that stands against it.
