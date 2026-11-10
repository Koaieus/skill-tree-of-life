---
id: 0084
title: An element does two things on a cast, shape and ride — ride plants terrain, shape reshapes the cast's own walk and plants nothing (Fire a disc, Lightning every node within N hops, Ice fewer hops for a dearer seed); one disc radius A × (√power + B) × node radius, A = 2, B = 1, has three readers; a shape and a primed node of the same element add into one go-off for which the node pays its solo cost, a different element's go-off is a second reach, concatenated; a go-off picks its nodes by shape alone and an arc transfers its Charge; Ice concentrate is a `ConcentrateUse` priced by one number per spell — supersedes 0081 §1 and §8 in part
status: accepted
date: 2026-11-10
deciders: owner
supersedes: [0081]
superseded-by: null
revisit-when: "the Fire shape's points multiplier (5, tentative) or the pass's at-least-1 floor on the solo cost reads wrong in play; double landings from two reaches prove too much (the dedupe switch flips to union); +50% per hop bites on a real spell; or shape-blind reach wants the owner's backup (allocated only at level 1, whole graph at 2+, Fire and Lightning together)"
sources: ["#1716", "docs/design/elements.md", "tools/disc_reach.py", "docs/handoffs/elements.md", "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md", "docs/adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md", "docs/adr/0070-an-intake-rows-load-use-is-a-swappable-resource.md"]
tags: [combat, on-hit, elements, status, reach, infusion, spells, architecture]
---

# ADR 0084 — An element does two things on a cast, shape and ride, and a shape composes with the node's go-off

## Context
ADR 0075 made reach terrain-only: a hit carries no reach, so an element on a cast could only plant stacks and wait for a later hit to set them off; its §2 left a bespoke use free to reshape the cast. ADR 0081 §1 priced a go-off at 1 stack per node reached and voided every spent stack, §7 gave a cast one element, and §8 priced Ice concentrate by an authored per-hop multiplier, a lean. Open were what an element does to the cast itself, how big a blast is (today's Explosive disc is 3 × √power × node radius and reaches nobody at power 1), what happens when a shaped cast lands on a node already primed, and whether a go-off reaches unallocated ground. Nothing elemental is built; the cost was docs and one probe (`tools/disc_reach.py`).

## Decision drivers
- **A hit carries no reach** (ADR 0075): no rule may make a landing choose a neighbour.
- **One size, many readers:** a blast, its light and a Fire-shaped cast read one radius, set for feel and never fitted to the procgen spacing.
- **Local + incoming is invariant:** a shape on a primed node of its own element is one bigger go-off, the same law for Fire, Lightning and Ice.
- **Pay once:** what the caster bought in points is never charged to the node in stacks.
- **A price the cast knows before it lands:** one authored number, never a measured landing count.

## Decision
1. **Ride and shape are independent, and a caster picks each** (owner, 2026-11-10: *"sometimes you'd want to set Fire as the reach element, sometimes you'd want to leave Fire stacks (Heat), sometimes you'd want both, or neither, or some other combination, all this *besides* other riders you might want to add -- poison, curse, greed, whatever (which don't modify reach)"*). Ride plants terrain on the cast's hits. Shape reshapes the cast's own walk at once and plants nothing: Fire widens the seed into a disc, Ice cuts hops and pays the seed, and Lightning's seed gathers every node within N hops (*"Lightning reach on a spell talks in *level*, where level N gathers up to N hops from target. level 1 -> ring 1; 2->ring 2. cost: {level} aka 1, +2 (3), +3 (6), etc"*). A shape acts on the walk, never on a hit, so ADR 0075's "a hit carries no reach" stands.
2. **One disc radius, r = A × (√power + B) × node radius, A = 2, B = 1, both knobs** (owner, 2026-11-10: *"`r(p) = A*(sqrt(p) + B) * node_radius` … edge hops have no min distance. euclidean has. so this might help?"*), read by three things (*"burning's go-off would be the same AoE radius here, as burning's light source, as well as the proposed "Fire reach" part of a spell"*). The Fire shape feeds it points × a multiplier knob (*"same shape, with multiplier. and the fit neednt be precise, the ballpark should feel right"*).
3. **A shape and a primed node of the same element add into one go-off** (owner, 2026-11-10: *"such that effective powers of local + incoming stay invariant basically. N lightning shape hitting level M Shocked node creates N+M level arc (e.g. 1+1=2, 2 hops out)"*). Fire adds the roots (owner's pick): r = A × (√(points × multiplier) + √excess + B) × node radius.
4. **The node pays its solo cost for the combined go-off** (owner, 2026-11-10: *"the solo cost"*): what its own go-off would have spent without the shape.
5. **A shape and a go-off of a different element are two reaches, concatenated, not deduplicated** — the dual-reach rule, with its one dedupe switch at the gather step (owner, 2026-11-10, picked *same as dual reach: concatenate*). The seed node takes the seed once, in full.
6. **A landing a shape adds carries what a go-off copy carries** (owner, 2026-11-10: *"same as what would happen if the cast had no reach but the node was Burning/Shocked"*): the go-off's share of damage and riders, the seed's crit, and it is a copy to a Frozen node.
7. **A go-off picks its nodes by shape alone, at every level**, unallocated nodes included (owner, 2026-11-10: *"so far just keep it shape blind always"*), and **an arc transfers its Charge**: each stack a Shocked go-off spends lands on the node it reached (*"knob, transfer by default"*). Burning and Frozen keep the void.
8. **Ice's shape is a `ConcentrateUse` on the spell's Ice intake row** (owner's pick, 2026-11-10; ADR 0070's open set): seed × (1 + bonus × hops removed), the bonus one number per spell, default 0.5 (*"a.. +50% boost for each hop removed. e.g. from 6->3 hops = -3 = +150% damage"*). It scales damage and aspect riders, never Heat, Cold or Charge stacks; 1 Ice = 1 hop, the rate authorable per spell; on a Frozen node the hops cut add to the shatter's excess, and the Ice seed is no breaker of its own (all owner's picks, 2026-11-10).

**Falls:** 0081 §1's void for a Shocked arc (its rejected *radiating transfer* stays dead for Burning's disc, where it mirrors diffusion) and its silence on unallocated nodes; 0081 §8's price. **Stands:** everything else in 0081, the 1-per-node cost law included.

## Consequences
- An element on a cast acts on the first hit instead of only ramping; a Fire shape with Heat riders lays Heat at share over its whole disc in one cast.
- Both same-element sums are superadditive in area: a 3-point Fire shape reaches about 9 nodes alone and about 17 on a node of excess 4.
- A small blast lives: power 1 reaches 0.7 other nodes on 150 px spacing and power 3 covers every neighbour, where ×3 reached none at power 1.
- A node inside two reaches lands riders and damage twice; an arc lays Charge on empty ground, and an interior wire node gets back what it gives, so decay and the conduct cost are what end a wire.
- Concentrating buys focus, far less than the walk it gives up: Pestilence 6 → 0 hops lands ×4 on a walk worth about 84 landings.

## Alternatives considered
### Today's ×3 disc, A = 2 B = 2, or a 1:1 fit of Fire points to Lightning levels
Lost on *one size*: ×3 hits nobody at power 1, B = 2 and the fit cover the whole neighbourhood from the first stack, and the fit ties the size to the map (owner: *"we are not here to settle on a shape based on the procgen settings"*).
### Two independent go-offs, the shape replacing the node's, Fire adding the powers, or excess counting as points
Lost on *local + incoming is invariant*: two go-offs double-land a neighbourhood and replacing wastes the node's stacks; Shocked's level is √(count / T), so N + M adds in the reach domain and adding the roots is its mirror. Dead.
### The node paying 1 per node the whole go-off reaches, or only for the nodes it added
Lost on *pay once*: the shape's part was paid in points.
### Union of a shape's reach and another element's go-off
Lost to the owner's dual-reach pick (2026-11-05: *"the double counting might be a feature!"*). **Most likely to be revived** — it is the kept switch.
### Voiding an arc's Charge (0081 §1), or allocated-only reach at level 1
The void lost to the owner's *transfer by default*; allocated-only is the owner's backup, not built — the `revisit-when`.
### A named set of presets, a per-hop ladder, or the measured L(H) / L(h) for Ice's price
Lost on *a price the cast knows*: one knob answers the owner's own worry (*"might need +100% in some cases, or +25% in others"*), and the measured form is ~84× for Pestilence at 0 hops.
### The Ice seed as a breaker, a spell-level concentrate field, or Ice on a cast as a plain Cold ride
The breaker lost on *local + incoming*: hops cut add to the shatter as every shape adds to its own element's go-off; the field lost to ADR 0070's open `LoadUse` set. Dead.
