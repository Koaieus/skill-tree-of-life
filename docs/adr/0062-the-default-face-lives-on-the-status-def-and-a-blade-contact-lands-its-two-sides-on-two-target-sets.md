---
id: 0062
title: An intake row's default face lives on the concept's StatusDef, not the aspect def; a blade contact's power splits into a striker's side on the board (under the landing's mask) and a node's side on the blade pieces (outside any mask), and a charged piece is armed, not fragile — supersedes 0061 in part
status: accepted
date: 2026-10-14
deciders: owner (the two sides, armed-not-fragile, StatusDef as home); pass (the module-deps grounds)
supersedes: [0061]
superseded-by: null
revisit-when: "A concept with no status needs a DETONATE default, or a blade contact's node side must reach a target set the landing's mask can name"
sources:
  - "#1608"
  - "#1609"
  - "#1611"
  - "docs/adr/0061-a-hits-explosive-load-resolves-through-the-intake-rows-face-and-a-blast-replicates-the-hit.md"
  - "docs/domain/explosive.md"
tags: [spells, aspects, infusion, combat, on-hit, melee, architecture]
---

# ADR 0062 — The default face lives on the StatusDef; a blade contact lands its two sides on two target sets

## Context

ADR 0061 put the default face "on the aspect def" and had every blast land "under the landing's own target mask". Building it (#1609, #1611) hit two walls: `attack/` may not reach up into `aspects/` (module-deps, gated by `check`), and a blade contact has a target set no mask names — the attacker's own blade pieces, which carry no ownership bit. This supersedes 0061 Decision points 1 (where the default lives) and 3 (the mask covers every blast target) only; the rest of 0061 stands.

## Decision drivers

- Modules depend only downward; `attack/` reads `effects/`, never `aspects/`.
- One spend/power formula for every hit source, blade contacts included.
- A tiny charge on one side must not turn the other side's huge load into a blast on both target sets.
- Peers replay a recorded result; a blade contact's verdicts are recorded, never re-derived.

## Decision

Owner, 2026-10-14 (#1609, comment 6178627285): *"Where it lives: on `StatusDef` (`effects/status/status_def.gd`), read through the row's `status()`."* — `effects/status/explosive.tres` authors DETONATE, the field defaults to PLANT, a concept with no status resolves PLANT.

Owner, 2026-10-14 (#1608, comment 6177810352), verbatim:

- *"100:0 -> 100 on board / 0 on blade; 100:1 -> 100+(1 shared) board / 1+(1 shared) blade"*
- *"having this one massive explosion be damaging to both defenders AND blade nodes just because of the teensy single explosive stack on the defender, feels off; something needs to work with the ratio between them"*
- Armed, not fragile: *"stripping explosive power to potentially 0 doesn't make sense. setting it off makes sense but isn't the most fun"* — the owner picked "armed, not fragile".

So:

1. **Default face.** `StatusDef.default_face`, resolved by `AspectIntake.face_of_status`; an int enum mirroring `AspectIntake.Face`.
2. **Two sides.** `power = (load + r·shared) + (present + r·shared)`. A hit that leaves nothing behind (arrow, spell) lands both on the board. A blade contact lands the striker's side on the board under the landing's mask and the node's side on the blade pieces around the struck node; it never reaches the board.
3. **Armed, not fragile.** A charged piece in the node side's reach is untouched; a plain one pops. Both reservoirs spend `max(1, shared)` (owner, #1608 comment 6176828602: *"both lose charges, at least 1"*).

## Consequences

- No upward import; the face default sits beside its `resonance` knob on one `.tres`.
- A blade's verdicts per piece (popped / spent / shrugged) are a recorded `Contact` row the replay draws, not a world mutation of their own.
- Two target sets for one contact cost a second reach pass in the blade gate.

## Alternatives considered

- **`Aspect.default_face` via an `AspectRoster` lookup (0061 point 1)** — lost on module-deps. Dead ground while `aspects/` ranks above `attack/`.
- **One blast on both target sets at full power** — lost on the ratio driver (the owner's "feels off"). Dead.
- **A charged piece in reach spends a life, or goes off** — the owner rejected both; the grenade-bouquet flail keeps every grenade for its own impact. Dead.
- **The piece spends exactly 1 per contact** — owner picked "same as the node". Revivable only with a new owner call.
