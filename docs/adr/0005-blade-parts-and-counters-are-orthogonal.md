---
id: 0005
title: Blade parts and their counters are orthogonal — bunkers destroy structure, never matter
status: accepted
date: 2026-09-08
deciders: owner+agent
supersedes: []
superseded-by: null
sources:
  - "#772"
  - "#785"
  - "#781"
  - "#409"
tags: [combat, melee, blade, design, balance]
---

# ADR 0005 — Blade parts and their counters are orthogonal

## Context

A melee blade is a phantom body with two kinds of part: **vertices** (phantom copies
of the wielder's `SkillNode`s, carrying every stat a node carries) and **edges**
(distance constraints between them, pure topology). The defender has two kinds of
counter: **spikes**, which kill an attacking vertex that lands on them, and
**bunkers**, an obstacle a blade cannot pass through.

Until #785, edges were inert — `melee_attack_plan.gd` said so in as many words:
*"D-1 MVP: edges are inert"*. That produced a real defect the owner named on
2026-09-07: an obstacle could slip *between* two vertices into the blade's interior
and then interact chaotically from the middle of a body that had no way to push it
out. #785 gave edges swept-capsule collision to close that.

But #785 also gave edges an offensive role (`edge_damage`, derived as the MIN of its
endpoints') and enrolled them in the spike system (edge `blunting`, likewise derived
as a MIN). Both derivations shipped live: `blunting` falls back to its `StatDef`
default of 1, so **every** edge stripped spikes and severed on a full drain with
nothing authored. That is what forced this decision.

## Decision

**Nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break edges.**

Two blade parts, two defensive counters, each pair disjoint. In the shorthand the
owner adopted it under: **a spike destroys matter, a bunker destroys structure** —
where *matter* is vertices (the nodes themselves) and *structure* is edges (what
holds them in a shape).

Four consequences, in order of how easily each is forgotten:

1. **An edge carries no stats.** Not derived from its endpoints by MIN, MAX or mean;
   not `blade_damage`, not `blunting`. Its *geometry* still derives from its endpoints
   — the capsule is trimmed to the rim of each endpoint's disc, and disc radius grows
   with allocation level — because geometry is physics, not offence.
2. **Edges never interact with spikes.** An edge sweeping over a spiked node drains
   nothing, severs nothing, and leaves the pool untouched.
3. **A bunker never pops a vertex.** On a rigid blade the *contact* is usually at a
   vertex, because discs stick out past the capsules trimmed to their rims. The vertex
   survives and cannot pass; the force goes into its incident edges, and the edge that
   cannot hold fails. **Contact point and failure point need not be the same** — that
   is what lets the split survive its hardest case without an exception.
4. **A spike never breaks an edge.** Symmetrically.

The failure criterion in (3) needs no new concept: in position-based dynamics the
distance-constraint residual *is* the strain, so the edge that stays violated across
the substeps — because the bunker will not let the vertex move — is the one that fails.

## Consequences

**Gameplay.** Ram a fully clamped truss into a bunker and it disassembles into a floppy
chain: every node kept, the ability to transmit force to the tip lost. This lands
exactly where #772 already arrived by another route — *rigidity is simultaneously the
payoff and the exposure*. The rigid blade is the one that hits hardest and the one a
bunker can take apart. A spiked defender and a bunkered defender now demand different
answers instead of both reading as "blade attrition".

**Build decisions stay distinct.** A truss and a chain with the same nodes differ only
in their edges. Had edges derived damage from their endpoints, triangulating for
rigidity would *also* have multiplied damage — rigidity would double-dip, and "add a
node for offence, add an edge for structure" would stop being a choice.

**Code that goes away rather than gets tuned.** #785's anti-double-dip arbitration —
*an edge emits only if it strictly out-damages the best particle touching the same
collider this substep* — exists solely because edges carry damage. Under this decision
it is unreachable: with no edge damage there is nothing to double-count. The
`edge_damage` `StatDef` and its board wiring go with it. `_sever_edge`,
`BladeState.removed_edges` and `remove_edge()` are **kept**, re-homed as #781's bunker
seam, preserving #785's invariant that severance is recorded rather than spliced out of
`state.edges` so every `edge_idx` stays stable and #795's one-adjacency-build-per-swing
survives.

**#409 (edge sharpeners) is now a deliberate exception to this record, not an
extension of it.** If a sharpened edge is ever wanted, it must argue against this ADR
on its merits. Its architecture is at least cheap: magnitude is a stat and belongs on
the `Entity` board; placement is topology and belongs on `Edge` as a boolean. No
third stat-bearing type. The open gameplay question it must answer is that a sharpened
edge would cut while sweeping over spikes unharmed, making sharpened edges the
anti-spike weapon.

## Alternatives considered

**Derive edge stats from the endpoints (MIN / MAX / mean).** What #785 shipped.
Rejected on the owner's lever test, 2026-09-08: two spiked balls on a lever deal
massive damage naturally, but *"the thin edge/beam connecting these 2 giant spiked
balls -> massive damage too orrrr no that makes no sense??"* An edge is not a blurry
average of its neighbours, and allocation level makes it starker — a level-3 node
carries +9 flat / x4.5 mult, none of which should reach the beam hanging off it. The
structural objection is the build-decision collapse above. **This ground is dead; do
not re-propose a gentler derivation.**

**Give edges blunting so spikes bite anywhere along the blade.** Rejected on the
owner's own arithmetic: a 10-node blade goes from ~10 spike interactions to ~19, a
truss more. And it is worse than a rate change — on a chain, severing edge *k*
disconnects everything past *k*, so it doubles the attacker's failure surface while
halving the defender's pool life. Both sides get whiplash from one rule.

**Keep edge blunting to remove "spacing luck" for spikes.** This was #772's and #785's
stated reason for it. **Retired 2026-09-08** by the owner, who argued the miss is not
exploitable: *"blades be floppy as heck, intentionally threading the spiked-defender
needle would be close to impossible, players wouldn't bet on it […] so many moving
parts it's almost guaranteed to hit, and if not, no biggie."* A blade is a multi-layer
floppy body; if the front rank misses, a second or third rank does not. The same
floppiness that made blade spine count `n` uncomputable in #772 is what makes the miss
unexploitable. Spacing luck for **bunkers** — an obstacle slipping into the blade
interior — was the real defect and is fixed by capsules.

**Let the bunker pop the contacting vertex.** Simplest, and the most readable hit
feedback, since the contact and the consequence coincide. Rejected because bunkers
would then do both jobs and the split would die the day it was adopted. A variant —
shed one incident edge per contact until the blade is floppy enough to flow around —
collapses back into the decision once "which edge" is answered with "the most strained".

**Edges deal velocity-based damage.** The owner's own pitch on #407, 2026-08-09:
*"edges being inert isn't a hardcoded MVP carve-out, it's the natural consequence of a
slow-moving/pivot-adjacent edge segment"*. Not rejected on its merits — it predates
this split by a month and was made when the alternative on the table was flat face
damage. #779 shipped the speed curve for vertices. Superseded here, and recoverable
through #409 if edge offence is ever wanted back.
