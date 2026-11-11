---
id: 0086
title: Every landing is a whole hit — a go-off's share defaults to 1 and each channel that goes off lands one more payload on its own node, so the hit node takes 1 + 1 per channel; a cast's shape alone is no channel, a same-element add-up is one, a break of Frozen is one, and dedupe sums a collateral's landings into one but never merges the hit node — supersedes 0084 §5's "the seed node takes the seed once, in full" in part
status: accepted
date: 2026-11-11
deciders: owner
supersedes: [0084]
superseded-by: null
revisit-when: "a share of 1 with the extra landings makes primed nodes die too fast to tune (the share is a knob per go-off), or the break's extra count wants to be 2 (owner floated it) rather than the default 1"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md"
  - "docs/adr/0084-an-element-does-two-things-on-a-cast-shape-and-ride-and-a-shape-composes-with-the-nodes-go-off.md"
  - "7b5c93e4, 68cfcb5c (design doc, 2026-11-10)"
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0086 — Every landing is a whole hit

## Context
ADR 0082 (2026-11-09) gathers a hit's target set and lands the payload once per entry at its share; ADR 0084 (2026-11-10) added that the seed node takes the seed once, in full, with a go-off's centre copy beside it. Nothing said what a share defaults to, how many times the node a go-off goes off from is hit, or what counts as a channel, so a blast could hit its own centre for less than its bystanders. Nothing elemental is built.

## Decision drivers
- **Central always more than the collaterals:** the target is never hit less than a node reached through a channel.
- **One model for every landing:** a hit, a blast copy and an arc copy are each a whole hit; no landing is a fraction.
- **No rounding on rider stacks:** a share of 1 leaves the per-rider round-up idle.
- **Terrain feeds nothing twice:** a fire does not feed itself, so stage one's once-per-node cap stands.

## Decision
1. **Whole hit** (owner, 2026-11-10, night, picked over share ½ and over share 1, each with the centre excluded): *"the hit hits *and* the blast hits, and the arc hits, and share 1 means no rounding for rider stacks"*. A go-off's share defaults to 1; each channel that goes off lands one more payload on the node it goes off from. The hit node takes 1 + 1 per channel (Burning's blast, Shocked's arc), a node one channel reaches takes 1, a node both reach takes 2. Terrain riders (Heat / Cold / Charge) still land once per node per hit, so extra landings carry damage and aspect riders only. "No other node reached, no go-off" stands. The share stays a knob per go-off, the dedupe a switch.
2. **The centre copy carries the go-off's own damage** as well as the payload (owner, 2026-11-10, batch 1: ticked the reading).
3. **Dedupe never merges the hit node's landings** (owner, 2026-11-10, batch 1): *"Deduping: central target takes 1 + (channels) loads, other nodes besides central take (share*channels) total load. Central always more than the collaterals (reached nodes through a channel)."* With the switch on, a collateral's entries merge into one landing at share × channels: every landing is the payload at a multiplier, its share, and dedupe sums a node's multipliers (owner, 2026-11-11, picked *one landing, summed*: *"If we ever tune the share (e.g. loses a fraction per hop for Arc or set some sweet spot for AoE disks idk) we'd sum those values anyway granted that the hits stay the same."*).
4. **A cast's shape alone is not a channel for the seed** (owner, 2026-11-10): *"the shape for spells hmmm i think that one shouldn't count"*. A shaped cast on an unprimed node lands once on its seed.
5. **A shape added into a primed node's go-off of the same element is that node's one channel**, so the seed takes 2 (owner, 2026-11-11, batch 3: ticked; it had been a tentative reading).
6. **A break of Frozen counts as a channel** (owner, 2026-11-10, batch 2): *"Break counts as a channel (or more radical: 2, more concentrated single target vibes) sounds like a fitting unification"*. The shattered node takes one more payload plus the burst; the extra count is a knob, default 1.

**Falls:** 0084 §5's "The seed node takes the seed once, in full" (it takes the seed plus one centre copy per channel). **Stands:** 0082 whole — the centre copies are gathered entries like any other, a node present twice still takes one landing per entry — and the rest of 0084: dual reach concatenated, the once-per-node cap on terrain, the 1-per-node cost law (ADR 0081). No ADR held a share value; 0.5 was the design doc's default only.

## Consequences
- Damage on a primed node doubles or triples (owner: *"damage doubles or triples, neat … and crits can stack on top of that"*); Frozen is tuned to match through its break.
- A node of rider-heavy payload takes extra landings of damage and aspect riders but never extra Heat, Cold or Charge.
- At share 1 the go-off's round-up per rider is idle; below 1 it applies again.
- A shaped cast on an unprimed node is no heavier than before; only priming adds the landing.
- Tuning has to price a primed node against a hit that now lands several whole payloads on it.

## Alternatives considered
### Share ½ with the centre excluded (the pre-call numbers)
Lost on *one model for every landing* and *no rounding on rider stacks*. **Most likely to be revived** if doubled damage proves too swingy; the share is a per-go-off knob, so it is a number change.
### Share 1 with the centre excluded
Lost on *central always more than the collaterals*: the target would take what its bystanders take.
### A cast's shape as a channel for its seed
Lost on the owner's call (2026-11-10): every shaped cast would land twice on its seed.
### Dedupe merging the hit node too, or keeping one entry at the share
Lost on *central always more than the collaterals*: merging could drop the hit node to a collateral's count. The union reading (a collateral two channels reach takes one landing at the share) lost on the owner's pick of the summed landing (2026-11-11).
### A break of Frozen adds nothing to the hit node
Lost on Frozen matching the doubling. The owner's *"or more radical: 2"* is the knob's other value, not a rejected option.
