---
id: 0031
title: Status resistance filters the accumulated float row on the host at each apply and tick, cancelling ⌈row × res − ½⌉ stacks; 100% blocks landing; never a per-hit scale at land
status: accepted
date: 2026-09-28
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "Stacks per hit grow large enough (tens) that per-hit rounding stops being all-or-nothing"
sources:
  - "#1157"
  - "#1190"
  - "docs/design/damage_over_time.md"
  - "combat/status_host.gd"
  - "attack/outcome/status_instance.gd"
tags: [combat, status, dot, balance, sync]
---

# ADR 0031 — Status resistance filters the accumulated row on the host at effect time

## Context

ADR 0022 decision 3 applied resistance once, at land, scaling each incoming hit's stacks, and #1156 made HP land floored. A landing carries 1–2 stacks per hit, so any rounding applied per hit is all-or-nothing. With a plain multiply, a single stack at 1% resistance becomes 0.99 and deals nothing. With the cancelled stacks floored, resistance below 100% never touches a single stack. ADR 0029 had already moved potency into the stacks stat's multiplier bins, so a landing is fractional anyway: 1 × +49% is 1.49. Resistance is the defender's number, one value per row, and both peers hold it live.

## Decision drivers

- **Legibility:** the health bar's projected DoT damage must equal what actually lands.
- **Small numbers:** 1–2 stacks per hit must neither be wiped out by a trace of resistance nor be immune to it.
- **Feel:** losing resistance should matter; being immune before the hit should mean nothing builds up.
- **Sync:** no new per-tick state or record fields; the authority decides at land, and every other rounding is deterministic.

## Decision

1. **The row is a float, and every place it bites is whole.** Damage floors at #1156's door, and the readout shows whole numbers. Owner call, 2026-09-28: *"Float row, whole where it bites"*.
2. **Resistance acts on the accumulated row when stacks take effect, not on each incoming hit.** `StatusHost` hands each def `row − cancelled` on apply and on every tick. Owner, 2026-09-28: *"option 1 seems best"*; *"1% res should never curb that to 0"*.
3. **It filters; the row stays intact** and decays from its unresisted size. Owner call, 2026-09-28: *"Filter, row intact"*.
4. **`cancelled = ⌈row × res − ½⌉`**: round half-down, so exact ties go to the attacker. Owner, 2026-09-28: *"is `rounding half-down` an option?"*
5. **At ≥100% resistance, stacks do not land.** The authority resolves power 0 and records it. Owner, 2026-09-28: *"100% blocks landing sounds fine"*.
6. **The projection runs the same per-tick function.** Owner, 2026-09-28: *"players can see expected poison damage in the health bar of affected nodes so this needs to reflect reality"*.

## Consequences

- Overturned: ADR 0022 decision 3's resistance clause. Its potency clause was already overturned by ADR 0029. Decisions 1, 2, 4 and 5 of ADR 0022 stand.
- Losing resistance makes the next tick count the full row, so resistance-shred becomes a combo. Resistance reaches curse, wither and blindness when they re-plant each tick, so a change takes up to one turn.
- `land_on` reads only the attacker, plus the host's 100% gate. Five status defs get resistance without per-def code.
- For whole rows, the survivors equal `round(row × (1 − res))` (half-up). Rounding only the cancelled part keeps 0% resistance a no-op on a fractional row.

## Alternatives considered

### Scale each hit at land (ADR 0022 decision 3)
**Rejected on small numbers and feel.** A lone stack at 1% deals 0 once the door floors, and losing resistance later changes nothing.

### Clear stacks from the row before each payload
**Rejected on feel and design budget.** It compounds (25% blocks about 35%), cleared stacks never come back, and it spends ADR 0022's reserved "resistance as faster decay" class identity. **The option most likely to be revived**, as that class identity.

### Integer row
**Rejected on small numbers.** `⌊1.49⌋ = 1` makes every +% stacks roll dead on 1-stack appliers, `cure_per_hp` mints fractions, and integer decay halves low-stack corruption and wither.

### Symmetric rounding of the cancelled count
**Rejected by owner pick.** 50% resistance fully blocks a lone stack, and exact ties go to the defender.
