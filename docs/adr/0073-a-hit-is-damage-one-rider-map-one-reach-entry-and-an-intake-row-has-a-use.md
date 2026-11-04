---
id: 0073
title: A hit is damage + one rider map (status id → stacks, aspect and element statuses alike) + one reach (element, load) resolved first; an element count is supply, never a per-hit load; an intake row is the one AspectIntake with a use ∈ ride / reach / shape, and a cast has one element slot that buys reach only
status: accepted
date: 2026-11-04
deciders: owner (three entries, count as supply, one separate element slot, slot buys reach only, every counted role rides); pass (row-use table wording)
supersedes: []
superseded-by: null
revisit-when: "A second reach per cast is wanted, or a fourth hit entry earns its place"
sources:
  - "#1716"
  - "#1733"
  - "#1694"
  - "#1660"
  - "docs/design/elements.md"
  - "attack/spell/aspect_intake.gd"
  - "attack/spell/load_use/"
tags: [combat, on-hit, spells, infusion, elements, status, architecture]
---

# ADR 0073 — A hit is damage + one rider map + one reach entry; an intake row has a use

## Context

Until elements, a hit carried damage and aspect riders, and a spell's `AspectIntake` rows (ADR 0060) loaded aspects; Firecracker's fuel row already carried a `use` (ADR 0070, `FuelUse`). Elements (#1716) add a count on the entity, a status family (ADR 0072) and *reach* — where a hit lands. #1733 R1 asks for one rider entry per status id; R2 forbids a sweep's every vertex blasting. The counts are meant to grow to 20–50, so anything reading one per hit scales with it. The open shape: how a hit carries element statuses and reach, and how a cast or the forge buys them.

## Decision drivers

- **Bounded reach:** reach per hit is paid for by a face, never granted by a stat (#1733 R2).
- **One rider path:** an element status rides exactly as an aspect status does (#1733 R1).
- **Readable casts:** a cast is a fire cast or a lightning cast, never both.
- **One row type:** reuse ADR 0060's `AspectIntake` and ADR 0070's `use` seam, not a parallel type.

## Decision

Owner, 2026-11-04: *"this is like "how Fire/Ice/Lightning ARE you really" counter, which likely ends up being a maximum/budget of sorts for some situation, but in most cases doesn't load automatically (maybe some cases would arise later? so far just none)"*. On the slot: *"managing reach does feel like something you'd wanna keep separate (and whose contribution in the Payload you'd wanna resolve first on landing the Hit) and maybe even restrict to 1 element at once"*; *"option 1 sounds best"*. On riders: *"if fuel is to be a fire status.. and option 2 says `fire:heat` at exactly one then how could a fuel-planting arrow exist? it couldn't. so i guess that rules out option 2? option 1 sounds reasonable"*. The three entries with one rider map: held, conditional on 1:1 aspects (*"depends on the status cardinality maybe"*), settled by ADR 0072. The element slot buys reach only: owner's pick over "reach plus the family's default status" and "reach only, ever" (elements.md § The forge).

1. **A hit has three entries:** damage (one number); riders (status id → stacks, one entry per id, aspect and element statuses alike); one reach `(element, load)`, resolved first.
2. **An element count is supply** a face draws from, never a per-hit load.
3. **An intake row is the one `AspectIntake`** plus a `use` ∈ **ride / reach / shape**.
4. **One element slot per cast**, separate from the aspect (INT) slots, buying reach only.
5. **Element-family riders are their own ride rows**, capped by the element count, one cap per element across its family. Every counted role (medium, mover) can ride; a state never.

Pass call (Claude, 2026-11-04): the row-use table's wording (ride → aspect slots, reach → element slot, shape → authored only). **Not decided here:** landing resolution (read / land / settle, dual reach) and Ice pricing stay pass proposals in `docs/design/elements.md`.

## Consequences

- Arrows, blade vertices and spell hits share one shape and one formula (`innate + floor(count × affinity)`).
- A zero-element build and an unloaded hit are untouched.
- Firecracker's fuel row becomes an ordinary `reach` row.
- A Heat-on-hit fire cast costs two rows (reach + ride), drawing on one cap.

## Alternatives considered

### The count as a per-hit load
Lost on *bounded reach*: a 30-vertex sweep would be 30 blasts (breaks #1733 R2). **Most likely to be revived** — the owner left room (*"maybe some cases would arise later?"*); a case that wants it is a face, not a stat.

### Shared slots / an N-slot element pool
Lost on *readable casts*: arcs-then-blast per hit becomes routine and unreadable; dual-element casts nobody asked for. A second reach is the `revisit-when`.

### Element riders in a second map, or "elemental" as its own payload category
Lost on *one rider path*: two maps fork every rider reader; damage stays one number.

### A separate `ElementIntake` type
Lost on *one row type*: the `use` seam already distinguishes rows.

### Reach plus a default family status per slot
Lost on *one rider path*: a slot that also plants a default member is a second, uncapped way to plant a status beside the ride rows; the owner picked separate ride rows over it.
