---
id: 0075
title: Reach is terrain-only — a hit is damage + riders; one side-less terrain stack per element (Heat, Cold, Charge) is inert up to T and primed past it (Burning, Frozen, Shocked), set off by any hit on it, a copy included, and copies carry everything; an intake row's use is ADR 0070's open `LoadUse` set; Fuel is an accelerant that never counts toward T; the per-node cap k × T, k = 2 + stake_level, is soft — supersedes 0073 and 0074 in part
status: accepted
date: 2026-11-08
deciders: owner (the threshold model, terrain-only reach, bespoke uses, Shocked to every neighbour, LET IT RIDE, Fuel as accelerant, the soft cap and its k; the 2026-11-05 terrain-hit, determinism and world-clock verdicts)
supersedes: [0073, 0074]
superseded-by: null
revisit-when: "copies carrying every stack build up more than the go-off spend, the cap and decay can tune out (owner: \"can change that later if it becomes too much\"), or an infusion needs a hit to carry reach of its own"
sources: ["#1716", "#1733", "#1735", "#1444", "#1660", "docs/design/elements.md", "docs/adr/0070-an-intake-rows-load-use-is-a-swappable-resource.md", "attack/spell/load_use/"]
tags: [combat, on-hit, elements, status, reach, infusion, determinism, architecture]
---

# ADR 0075 — Reach is terrain-only: a terrain stack is inert to T and primed past it

## Context
ADR 0073 (2026-11-04) gave a hit a third entry, one reach `(element, load)` resolved first, and wrote a row's use as the closed set ride / reach / shape, though ADR 0070 had already made it an open set of `LoadUse` classes and the shipped `CleanseUse` fits none of the three. ADR 0074 (2026-11-05) had Cold absorb arriving reach one for one, Frozen at Cold ≥ degree + 1 as a glass ceiling, a hard cap k × T with k a knob, and Heat deleted on unallocated ground. An infused Charge reach then had to pick which neighbour an arc strikes (a seeded "fickle" third key), every landing summed two reach sources (the hit's entry and the node's media), and Cold reacted to sub-T hits where Heat and Charge did not: three laws for three elements. Nothing elemental is built, so changing the shape cost docs only.

## Decision drivers
- **One reach source:** where copies land is read off the node alone, so no hit needs a pick rule.
- **Open set:** a new way to spend an infusion is a new `LoadUse` class (ADR 0070), never an enum value.
- **One threshold law:** the three elements share one T, one cap and one capacity bar; under T a stack only feels.
- **Bounded buildup:** the brakes are the go-off spend, the cap and decay — no per-link decay, no rider filter.
- **One snapshot, deterministic terrain:** read / land / settle stays pure (#1733 R4); a terrain cascade has no crit and no pick, so every peer reproduces it.

## Decision
Owner, 2026-11-08: *"make them all inert before some threshold T is passed. when "elemental terrain-reach stacks" (== cold/heat/charge stacks) exceed T, then they become primed -- the derived status … this derived effect has a "trigger" and if triggered it performs (generally) a reach-based action, and finally, each triggering has a stack-cost … this derived status IS the reach face of the element. without it, no reach effects"*. On reach: *"Think that charge settles it in favor of the "there's 1 and its just the terrain stacks": if 1 "charge as direct arc reach" is infused it reintroduces "which one neighbor then?" While a system where "charge Level = 1" means you got enough to hit *all* nbs."* On uses: *"spell infusions may also do bespoke stuff instead of simply adding riders, we are free to design what feels useful and fun to have"*.

1. **A hit is damage + riders** (one rider map, status id → stacks) and carries no reach; reach is read off the node it lands on.
2. **An intake row's use is ADR 0070's open `LoadUse` set.** A ride row planting Heat, Cold, Charge or Fuel is one use; a bespoke use (Firecracker's waves, Ice concentrate) may reshape the cast but never gives a hit a reach entry. Ice altering a cast is such a use (owner, 2026-11-05: *"something that takes the ice-suppression value and uses it to alter the cast spell?"*).
3. **One side-less terrain stack per element** — Heat, Cold, Charge — inert up to T, primed past it (count > T) as Burning, Frozen, Shocked, derived at every read, never saved. Cold under T absorbs nothing. Heat is terrain as Cold is: it rests on unallocated ground, and every node cools toward zero (owner, 2026-11-08: *"if we make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it should eventually cool off"*).
4. **The trigger is a hit on a primed node, a copy included**: Burning explodes over a disc; Shocked arcs to every neighbour (owner, 2026-11-08: *"it will arc to *all its neighbors* each time it is hit"*), so the arc pick rule is retired; Frozen denies arriving reach and ends a path.
5. **Copies carry everything**, element stacks included, chained links flat (owner, 2026-11-08: *"everything rides yeah, LET IT RIDE! can change that later if it becomes too much"*; 2026-11-05, shown a Charge copy re-laying the wire its go-off spent: *"Leaning 2. My reasoning: if buildup is too strong we can always tune up decay rates/mechanisms"*). An Ice-loaded seed on a primed node is copied like any payload (2026-11-05: *"ice + fuel sounds like a combo why not?"*).
6. **Fuel is an accelerant** (owner, 2026-11-08: *"fuel indeed doesnt count towards burning"*): when its node explodes, *"consume all fuel stacks too add them to the explosive power, and leave residual heat"*, and *"burning holding fuel explodes"* (2026-11-08; 2026-11-05: *"Burning ignites"*).
7. **The cap is k × T, k = 2 + `stake_level`, and soft** (owner, 2026-11-06: *"k = 2 (base value) + stake_level (statformula)"*; *"a 2nd "post cap" state sounds good too … the excess is there but burns off quickly"*): stacks past it are the overflow and decay fast, not wasted.
8. **A go-off with no parent hit is a terrain hit** (owner, 2026-11-05: *"option 1"*): the blast's own damage, no riders, no crit, side-blind, synced by determinism (*"no crit on unallocated nodes doing things. but even if they did, we shouldve found a way to sync the seed (perhap during turnmanager ticks) such that it is deterministic anyway"*). Diffusion, decay and the terrain settle run on the world turn as built (owner, 2026-11-05: *"option 1"*).

**Stands:** 0073 §2 (count is supply), §5 (every counted role rides, one cap per element) and the one row type; 0074 §1 (read / land / settle; read now sees only the node's primed states), §2 (dual reach concatenated, tentative) and §6's one signed temperature. **Falls:** 0073 §1's reach entry, §3's closed set, §4's element slot buying reach; 0074 §3, §4's degree + 1 threshold and glass ceiling, §5's knob k and hard cap, §6's Heat sink.

**Not decided here:** what a go-off pays per element (1 per trigger or ½T = degree, and whether a spend may take a node below T); how a shatter turns excess into damage; Ice concentrate's shape; with 0073 §4's slot gone, whether element rows take the aspect slots and how many elements one cast carries. Tunables, not recorded: T = 2 × degree, N = 2 Heat per Fuel, decay rates, the size ladder.

## Consequences
- An arrow, a blade vertex and a spell hit share one payload shape and none carries reach; a zero-element build sets off terrain others primed, its own hits unchanged.
- One threshold for all three elements: one capacity-bar shape, one rule bounding a blast, a chain and a Cold wall.
- An AoE infusion ramps (early hits warm the ground, later hits blow it) instead of arriving with the first hit.
- A Charge copy re-lays the wire its go-off spent, so no terrain stack ships without a decay; buildup is tuned by rates, not structure.
- 0073's "Firecracker's fuel row becomes a `reach` row" is void: no use buys reach.

## Alternatives considered
### A reach entry on the hit (0073 §1, §4)
Lost on *one reach source*: infused Charge reach reintroduces "which one neighbor", and each landing sums two sources. 0073's *bounded reach* survives in terrain form: a stat never grants reach.
### The closed use set ride / reach / shape (0073 §3)
Lost on *open set*: `CleanseUse` already fits none, and the owner wants bespoke infusions. Dead.
### Cold absorbing sub-T reach; Frozen at degree + 1 as a glass ceiling (0074 §3, §4)
Lost on *one threshold law*. Whether a big enough reach breaks Frozen is reopened in the design doc, not rejected.
### An arc pick rule (a seeded "fickle" third key among ties)
Lost on *one reach source* and *deterministic terrain*: Shocked strikes every neighbour, no pick, no seed. Dead.
### A copy carrying every rider except the stack its go-off spent; per-link decay `s^k`
Lost on *bounded buildup*: the owner keeps the brakes in the spend, the cap and decay. **Most likely to be revived** — the owner's own hedge, the `revisit-when`.
### Fuel counting toward T; +1 Heat on every node a disc touches
Fuel toward T lost to the owner's line above; +1 Heat per disc node lost to the owner's pick (2026-11-08) of N Heat per Fuel on its own node, on *bounded buildup*: it makes Heat from nothing.
### A hard cap that wastes the surplus (0074 §5)
Lost to the owner's soft cap (2026-11-06): the overflow is a visible, fast-decaying band, so 0074's "a 100-Cold wall is nigh impossible to remove" is still answered by the cap.
