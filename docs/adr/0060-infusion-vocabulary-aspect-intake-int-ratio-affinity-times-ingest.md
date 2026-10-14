---
id: 0060
title: A spell's intake row is an AspectIntake on the concept's Identity; load = innate + floor(infusion × ingest × affinity), both rates int:int and multiplied
status: accepted
date: 2026-10-13
deciders: owner (the five terms, multiplying rates, int:int only, shaping-only rows); pass (`AspectIntake` points at the `Identity`, field names)
supersedes: [0047]
superseded-by: null
revisit-when: "A spell needs a rate no small int:int pair expresses, or a per-source (innate vs infused) intake flag"
sources:
  - "#1593"
  - "#1597"
  - "#1250"
  - "docs/domain/aspect-cell-authoring.md § Infusion"
tags: [spells, aspects, status, infusion, architecture]
---

# ADR 0060 — Infusion vocabulary: AspectIntake, int:int affinity × ingest rate, load

## Context

ADR 0047 made infusion a per-cast spell component: `SpellDef.affinities: Array[SpellAffinity{status, innate, rate}]` plus a float `default_rate` used as a fallback for unlisted concepts, and `Infusion.affinity_of` for the result. "Affinity" named the row, the rate and the final count at once. A row pointing at a `StatusDef` cannot list Explosive, which has no status, so Explosive's infusion face (#1466) could not be authored. Everything else in 0047 (slots from INT, supply from `<concept>_aspect`, nothing consumed, no `SpellDef` authors an `ApplyStatusEffect`, riders after `on_hit_effects`) stands.

## Decision drivers

- One word per quantity, so the tray, tooltip and code read the same.
- Exact, reproducible arithmetic: a peer reproduces every load (ADR 0002).
- A row must be able to name any concept, status or not.
- Inspector-editable, with the four template spells' numbers unchanged.

## Decision

Owner, 2026-10-13, on #1593, verbatim:

- *"i need more strict usage of "affinity" vs "innate" vs "infusion" vs "whatever the final value becomes" … affinity to me feels like it could fit the authored starting amount OR the exchange rate OR the final value"* — and, on the proposed glossary, *"Pin it"*.
- *"Multiply: base × per-aspect"*
- *"the exchange rate needs to be in int:int only i think (no 1.01 or 1:1.1? would complicate things bigtime)"*

Owner, 2026-10-13, on #1597: *Firecracker's explosive is fuel, not cargo* — a row can mark its load as shaping the spell only.

So:

1. **innate** = the spell's authored starting amount of a concept; **affinity** = the per-concept exchange rate (0 refuses); **ingest rate** = the spell-wide exchange rate; **infusion** = what the caster adds this cast; **load** = `innate + floor(infusion × ingest × affinity)`.
2. The row is **`AspectIntake{identity, innate, affinity_gain, affinity_cost}`** in `SpellDef.intakes`; the spell carries `ingest_gain` / `ingest_cost`. All four are ints, costs ≥ 1. The load is integer arithmetic: `innate + (infusion × a_gain × i_gain) / (a_cost × i_cost)`, floored.
3. **Rates multiply**; an unlisted concept has affinity 1:1, so ingest alone applies. Ingest is no longer a fallback.
4. `Infusion.load_of(spell)` replaces `affinity_of`; `riders` emits one `ApplyStatusEffect` per concept whose load is above 0 and has a status (`StatusRoster.by_concept`) — except a row marked shaping-only (`rides = false`, #1597), whose load lands no rider and is read by the spell's shape instead. The flag is per row, never per source.

Pass call (Claude, 2026-10-13, revisable): **the row points at the concept's `Identity`**, as `aspects/aspect.gd` asks of every facet; the status resolves by concept id.

## Consequences

- Explosive (no status) can be listed; its load reaches the cast without a rider.
- Every rate is exact: `2.0 → 2:1`, `0.5 → 1:2`, `0.1 → 1:10`. No float rounding on a peer.
- Readouts say "affinity" for a rate and "load" for an amount; `Infusion.rate_of` survives only as a display / refusal float.

## Alternatives considered

- **Keep `default_rate` as a fallback** — rejected by the owner ("Multiply"); a many-hit spell could not thin every concept at once.
- **Float rates** — rejected by the owner (int:int only).
- **Keep `status: StatusDef` on the row** — cannot list a concept without a status (Explosive).
