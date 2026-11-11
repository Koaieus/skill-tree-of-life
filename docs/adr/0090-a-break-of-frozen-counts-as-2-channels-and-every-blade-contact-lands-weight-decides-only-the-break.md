---
id: 0090
title: A break of Frozen counts as 2 channels by default (a knob or const), so the shattered node takes two more payloads plus the burst; every blade contact on Frozen lands as a normal hit and the vertex's weight decides only whether the touch breaks the ice, so a lighter vertex lands its payload as a plain hit — no break, no burst, no extra landing — then pops — supersedes 0086 §6's default of 1 and fills 0088 §5's unaddressed lighter vertex
status: accepted
date: 2026-11-11
deciders: owner
supersedes: [0086, 0088]
superseded-by: null
revisit-when: "a break worth 2 channels makes Frozen a cheaper single-target kill than priming Burning or Shocked (the count is a knob or const), or a light vertex's plain hit plus its pop proves too strong or too weak against Frozen"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0086-every-landing-is-a-whole-hit-a-go-off-shares-at-1-and-lands-on-its-own-node-too.md"
  - "docs/adr/0088-a-blade-vertex-breaks-frozen-only-if-at-least-as-heavy-as-the-node-a-lighter-one-snaps-and-the-ice-holds.md"
tags: [combat, on-hit, melee, blade, elements, status]
---

# ADR 0090 — A break of Frozen counts as 2 channels; every blade contact on Frozen lands

## Context
ADR 0086 §6 (2026-11-10) made a break of Frozen count as a channel, so the shattered node takes extra payloads plus the burst, with the count a knob at default 1; its `revisit-when` named the owner's *"or more radical: 2"*. ADR 0088 (2026-11-10) gated a blade vertex's breaking touch on weight and had a breaking touch land as a normal hit before the vertex pops, but left a lighter vertex's contact, where the ice holds, unaddressed; the design doc carried a tentative "the spike pop refuses the contact". Nothing elemental is built.

## Decision drivers
- **A shatter is aggressively single target:** breaking the ice should pay more than a node one channel already gives.
- **One rule for every blade contact:** the touch lands the same way whether or not it breaks the ice.
- **Melee must stay viable against Frozen** (ADR 0088): a thin blade is not blanked outright.
- **A tuning number stays a number:** the count is retuned without a new rule.

## Decision
1. **A break of Frozen counts as 2 channels by default** (owner, 2026-11-11, on +1 or +2: *"+1 is what a 1-burning node would get already. Shatter is aggressively single target."*, then *"2 for now sounds good. Can retune later, most likely a knob or const"*). The shattered node takes two more payloads of the hit that breaks it, on top of that hit's own landing, plus the burst; the extra landings carry damage and aspect riders only (ADR 0086 §1). The count is a knob or const.
2. **Every blade contact on Frozen lands as normal; weight decides only whether the touch breaks the ice** (owner, 2026-11-11, picked *lands as a plain hit*). A lighter vertex, where the ice holds, lands its payload as a plain hit — no break, no burst, no extra landing — and then pops.

**Falls:** 0086 §6's *"the extra count is a knob, default 1"*; 0088 §5's *"A lighter vertex's refused contact is not addressed"*. **Stands:** the rest of 0086 §6 (a break counts as a channel, the knob); 0088 §1–§4 (the weight gate, a lighter vertex snaps and the ice holds, only the touch gated) and §5's breaking touch landing before the pop.

## Consequences
- A hit that breaks the ice lands three payloads on the node plus the burst, against two for a hit setting off a node with one channel.
- A light vertex whose contact crits or clears the flat threshold breaks the ice through those breakers (ADR 0088 §4) and so lands as a breaking hit: its payload, the break's two extra landings and the burst, then the pop.
- A thin blade against Frozen trades its vertex for one plain hit: the ice still holds, but the contact is never wasted.
- The spike pop on first contact stays; only what the contact lands is settled.

## Alternatives considered
### A break counts as 1 channel (ADR 0086 §6's default)
Lost on *a shatter is aggressively single target*: +1 is what a node with one channel already gives. **Most likely to be revived**: the owner expects to retune, and it is the same knob at another value.
### A lighter vertex's contact is refused by the pop (the doc's tentative reading)
Lost on *one rule for every blade contact*: the touch would land or not depending on weight, not only the break.
### A lighter vertex deflects off the ice like a defender plate
It deals nothing and nothing breaks. Not rejected here: it stays ADR 0088's named fallback if the snap nerfs melee too much.
