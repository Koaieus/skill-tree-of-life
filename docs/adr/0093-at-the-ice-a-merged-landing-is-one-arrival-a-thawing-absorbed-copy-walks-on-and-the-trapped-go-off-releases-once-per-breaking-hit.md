---
id: 0093
title: At the ice a dedupe-merged landing is one arrival at its summed multiplier, an absorbed copy whose Heat thaws the ice walks on, and the trapped go-off is released once for each hit that breaks it (tentative); a blade vertex's element is a shape on the node it hits; an arc pays only for the nodes it reaches
status: accepted
date: 2026-11-11
deciders: owner
supersedes: [0087]
superseded-by: null
revisit-when: "playtest finds one release per breaking hit too strong (fallback, the owner's: each hit collects every node its cascade reaches into one union per channel, blasts and arcs separately, so a node lands once per channel per hit), or a blade vertex read as a shape on the node it hits plays wrong"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0091-a-frozen-node-settles-once-per-generation-over-all-its-arrivals-and-the-damage-breaker-reads-each-arrivals-raw-amount-alone.md"
  - "docs/adr/0092-within-a-beat-all-damage-lands-before-any-aspect-rider-so-the-ice-reads-the-floater-and-a-depleted-node-takes-no-aspect-riders.md"
  - "docs/adr/0086-every-landing-is-a-whole-hit-a-go-off-shares-at-1-and-lands-on-its-own-node-too.md"
tags: [combat, on-hit, elements, reach, blade, determinism]
---

# ADR 0093 — Five follow-ups beside ADR 0091: the merged landing, the thawing copy, the release count, the blade vertex, the arc's spend

## Context
ADR 0091 settled a Frozen node once per generation, but left the dedupe-merged landing's break test unsaid, ADR 0087 listed as not decided whether an absorbed copy whose Heat thaws the ice still ends its path, and a node both Frozen and Shocked had no count for how often the break releases its trapped go-off. Arrows never share a beat (one beat per schedule entry, `outcome_schedule.gd`); only a magic wave puts several hits in one generation. A blade vertex's element (a Burning disc, a Shocked arc) had been read as the blade node going off, giving an unprimed contact node 2 landings. A level-2+ arc stopping at a node whose path ends had no rule for the Charge of the hops it never makes. Nothing elemental is built.

## Decision drivers
- **Order independence** within a beat (ADR 0091).
- **One go-off count:** a Frozen node releases on the count an unfrozen node goes off with, once per hit.
- **The read after the riders,** as at every node: the path ends only at ice that is still there.
- **The dedupe's one landing is one arrival.**
- **An explosion belongs to the node hit:** one bigger blast, not two.
- **Spend follows landings:** no Charge lost into a wall.

## Decision
1. **A dedupe-merged landing is one arrival at its summed multiplier** (owner, 2026-11-11, picked: *"the merged landing IS the arrival: its 2x amount is tested once"*), read mitigated (ADR 0092 §2). With dedupe off the entries are separate arrivals, each tested alone.
2. **An absorbed copy whose Heat thaws the ice walks on** (owner, 2026-11-11, picked: *"a path ends at Frozen only if the node is still Frozen after the arrival's terrain riders"*).
3. **The trapped go-off releases once per breaking hit** (owner, 2026-11-11, picked: *"The ice releases its trapped go-off once for each hit that breaks it."*; then *"mark it as tentative, given playtesting will see if this is ok or needs to be toned down"*). The node still shatters once with one burst (ADR 0091 §1); each release carries the payload of the hit that set it off; a hit the ice absorbed sets nothing off and walks on through the shattered node.
4. **A blade vertex's element is a shape on the node it hits** (owner, 2026-11-11: *"do we let *the blade node* explode, or let *the node it hits* explode? The latter points to a shape and is easier to do esp if a burning blade hitting a burning node causes a *bigger* explosion instead of 2 explosions"*; a Shocked vertex picked the same). An unprimed contact node takes 1 landing; on a primed node of the vertex's element the shape adds into its go-off as one channel (ADR 0086 §5); on Frozen the shape runs alone.
5. **An arc pays for what it reaches** (owner, 2026-11-11, picked *spend follows landings*): Charge is spent and transferred only for the nodes the arc reaches; the rest stays on the source.

**Falls:** 0087's *"whether an absorbed copy's path ends only if the node is still Frozen after its riders"* (not decided there). **Stands:** the rest of 0087 and 0091.

## Consequences
- A wave that breaks a Frozen + Shocked node with two hits sets off two releases, as two hits on an unfrozen Shocked node go off twice.
- Heat is a way through ice even on a copy too weak to break it.
- A Burning blade on a Burning node is one bigger blast; a blade's terrain goes off where it lands, sized by that node.
- A wall stops an arc without eating the source's Charge.

## Alternatives considered
### One union per channel per hit (the owner's toning-down shape)
Each hit collects every node its cascade reaches into one union per channel, so a node lands once per channel per hit. **Most likely to be revived,** by the playtest in `revisit-when`.
### One release per generation, the heaviest breaker's payload under a tie rule
Lost on *one go-off count*. Its ground is dead: the option claimed it matched "once per hit", but two same-beat hits on an unfrozen node both go off.
### Each merged channel tested alone
Lost on *the dedupe's one landing is one arrival*.
### An absorbed copy's path ends however its Heat leaves the ice
Lost on *the read after the riders*.
### The blade node goes off, centred on and sized by the vertex
Lost on *an explosion belongs to the node hit*: a Burning vertex on a Burning node made two blasts and an unprimed node took 2 landings.
### The arc pays for its whole shape at the read
A simpler seat; lost on *spend follows landings*.
