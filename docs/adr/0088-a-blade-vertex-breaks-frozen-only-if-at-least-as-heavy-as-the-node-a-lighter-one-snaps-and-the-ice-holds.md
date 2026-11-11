---
id: 0088
title: A blade vertex's touch breaks Frozen only if the vertex is at least as heavy as the node (a tie breaks); a lighter vertex still snaps and the ice holds; only the touch is gated, so a light vertex's crit or threshold damage still breaks it; a touch that breaks the ice lands as a normal hit, then the vertex pops — supersedes 0081 §3's ungated "blade vertex's touch" in part
status: accepted
date: 2026-11-10
deciders: owner (the weight gate, the lighter vertex snaps and the ice holds, only the touch gated, Bunker counts, a breaking touch lands); pass (the mass formula, build-time read, what counts as per-contact)
supersedes: [0081]
superseded-by: null
revisit-when: "the gate nerfs melee too much against Frozen (the fallback is the lighter vertex deflecting off the ice like a defender plate: it deals nothing and nothing breaks)"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md"
  - "docs/domain/melee-blade-sim.md"
tags: [combat, melee, blade, elements, status]
---

# ADR 0088 — A blade vertex breaks Frozen only if at least as heavy as the node

## Context
ADR 0081 §3 (2026-11-09) made a blade vertex's touch one of three things that break Frozen, beside any crit and a flat damage threshold. The touch took no account of size: any vertex, however small, shattered any node it met. On 2026-11-10 the owner added a size condition, so a thin blade tip could no longer pop ice grown on a large node. Nothing elemental is built.

## Decision drivers
- **Size should matter:** a light vertex shattering a heavy node is not the fragile snap the owner wanted.
- **Melee must stay viable against Frozen:** the gate must not wall melee off from the element.
- **Use the weight the sim already has:** no second weight definition for the blade.
- **The three breakers stay independent:** the crit and the threshold are facts of the hit, not of the vertex.

## Decision
Owner, 2026-11-10: *"melee blade nodes shatter frozen nodes they hit *only if their radius is equal or larger than the node they hit* (specifically: if they have more weight; ignoring temporary modifications by e.g. passing over Cold (but not frozen) nodes)"*.

1. **The touch breaks the ice only if the vertex is at least as heavy as the node.** *"Equal or larger"* means a tie breaks.
2. **Weight is the blade sim's mass, `(radius / 32)²`**, read at build time: the vertex's from its source node's radius times Bunker's `blade_mass`, the node's from its own `SkillNode.radius`. *Pass's reading, not an owner sentence:* the formula and the build-time read. This is not `1/inv_mass`, which is 0 for pivot and dead vertices. The owner picked *Bunker counts* (a build choice, not a temporary modifier). Nothing per-contact enters the weight, Cold's drag included, because the owner's sentence ignores temporary modifications.
3. **A lighter vertex still snaps and the ice holds** (owner picked *snaps, ice holds* from the options offered).
4. **Only the touch is gated** (owner picked *only the touch is gated*): a light vertex's contact that crits, or that would deal damage at or above the flat threshold, still breaks the ice.
5. **A touch that breaks the ice lands as a normal hit, then the vertex pops** (owner, 2026-11-11: *"Frozen is a boon for defender: it snaps the blade. But it cuts too: it takes increased damage. … So basically bladd node should land as normal but with a guaranteed shatter (and then pop)"*): its payload lands, the break counts as a channel and the burst lands (ADR 0086 §6), and only then does the vertex snap. A lighter vertex's refused contact is not addressed.

**Falls:** 0081 §3's ungated "a blade vertex's touch". **Stands:** the rest of 0081 §3 (the crit and flat-threshold breakers, direct hits and arriving copies alike), §2's burst, and the spike pop on first contact.

## Consequences
- A heavy node (a staked or grown one) is safe from a light blade's touch; a build that wants to shatter it brings a heavier vertex, a Bunker's `blade_mass`, or a crit.
- Frozen is a soft counter to thin blades, not a wall: they lose their vertex and the ice holds, but they can still break it by crit or damage.
- Melee's weight is read once at build, so Cold's drag cannot swing a touch from break to hold mid-swing.
- A Bunker's `blade_mass` becomes a lever against Frozen as well as against structure.
- Against ice a heavy blade trades a vertex for a boosted hit (payload, break channel, burst): a boon and a nerf at once, not a pure loss.

## Alternatives considered
### The lighter vertex deflects off the ice like a defender plate
It deals nothing and nothing breaks. Lost on *melee must stay viable against Frozen*: a thin blade would be blanked outright. **Most likely to be revived** if the snap proves to nerf melee too much; it is the `revisit-when`, the owner's named fallback, not a dead ground.
### Every touch breaks the ice (0081 §3 as it stood)
Lost on *size should matter*: a point-sized vertex could shatter any node.
### Gate all three breakers on weight
A light vertex's crit or threshold hit would also hold. Lost on *the three breakers stay independent* (owner picked *only the touch is gated*).
### Weight from the live simulation (`1/inv_mass`, or including Cold's drag)
Lost on *use the weight the sim already has* and on the owner's *ignoring temporary modifications*: pivot and dead vertices read 0, and a drag would flip the result mid-swing.
