---
id: 0032
title: Status stacks are integers — the row stores an int, and a def derives any fractional effect (blindness's %) from the count; no second float field
status: accepted
date: 2026-09-30
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "A status appears whose stored state cannot be expressed as a whole count plus a per-def curve"
sources:
  - "#1217"
  - "#1203"
  - "docs/adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md"
  - "combat/status_host.gd"
  - "effects/status/blindness.gd"
  - "effects/status/armor_break.gd"
  - "systems/vision_system.gd"
tags: [combat, status, dot, balance]
---

# ADR 0032 — Status stacks are integers; a def derives any fractional effect from the count

## Context

ADR 0031 decision 1 kept the status row a float ("Float row, whole where it bites") and rejected an integer row on three grounds: `⌊1.49⌋ = 1` kills every +% stacks roll on 1-stack appliers, `cure_per_hp` mints fractions, and integer decay shortens low-stack corruption and wither. Two defs stored a genuine fraction: `armor_break` (`power` *is* the fraction of armor removed, capped at 1.0) and `scouted` (`power = radius / SCOUT_FLOOR`). Blindness already mapped a count to a percentage through `factor_for(power)`.

## Decision drivers

- **Legibility:** a stack is a thing a player counts; poison deals 1 per stack per tick.
- **No display rounding:** a fractional row needs rules for how many decimals to show, and those hide the part that later multiplies into a whole.
- **Storage follows content:** an int slot only if every concrete status fits it.

## Decision

1. **A stack is an integer, canonically.** Owner, 2026-09-30: *"in my mind, a stack is always integer. canonically. poison dealing 1 damage per stack per tick -> intuitive."*
2. **The row's type follows the content.** Owner, 2026-09-30: *"if ALL stacks are ints, change it to int. if ANY concrete status needs a float for that slot, we can't use int."* Every def fits: `armor_break` goes flat (−1 armor per stack, uncapped; owner, 2026-09-30: *"90 armor being reduced to -10 (at 100 stacks of -1) feels better"*), and `scouted` goes to count stacks (owner, 2026-09-30: *"scouting could well be served with (open ended) integer stacks"*).
3. **No second stored `intensity`.** A def whose effect reads as a percentage derives it from the count, as blindness's saturating curve already does.

## Consequences

- Overturned: ADR 0031 decision 1. Its decisions 2–6 stand; `⌈row × res − ½⌉` already yields an integer.
- The integer-row rejection's grounds are dead or accepted: procgen is authored to roll mostly whole stacks (owner: *"we have full control over what modifiers we add to procgen"*), `cure_per_hp` retires in favour of an authored cure amount, and decay shape is a per-def slot tuned against whole stacks.
- A +% on stacks per hit only matters once the product crosses a whole number; small rolls on 1-stack appliers are inert.
- Every site that multiplies stacks (landing fold, fractional decay, spread) needs a stated rounding direction.
- Rows replay identically across peers with no float drift.

## Alternatives considered

### Float row, whole where it bites (ADR 0031 decision 1)
**Rejected on legibility and display rounding.** *"2.5 is one thing, but 2.25 is another and 2.235999 is yet another"* (owner, 2026-09-30). **The option most likely to be revived** if a content need for sub-stack precision appears.

### Split the row into an int `stacks` plus a float `intensity`/`power`
**Rejected on storage-follows-content.** Raised by the owner as the real question; every current def's fraction is either derivable from the count (blindness) or is being redesigned as a count (armor break, scouted), so the second field would duplicate a per-def function.
