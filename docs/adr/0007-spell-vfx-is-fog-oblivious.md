---
id: 0007
title: Spell VFX is fog-oblivious — every spell visual draws over fog, or none does
status: accepted
date: 2026-08-30
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#670"
  - "#413"
  - "ff08be3"
  - "docs/domain/spell-vfx-kit.md"
tags: [vfx, spells, fog, rendering]
---

# ADR 0007 — Spell VFX is fog-oblivious

> **Backfilled 2026-09-09** from `docs/domain/spell-vfx-kit.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

The shared spell-VFX kit (#670) added `EdgeEnergize`, an overlay that paints a
travelling front along an edge. Fog of war already exists as `FogOverlay`, and
#413 had built `ui/vision_field.gdshaderinc` precisely so a shader could ask
whether a world position is visible — so the machinery to make a new spell visual
fog-aware was sitting there, one `#include` away.

The question was whether to use it. It was not a question about `EdgeEnergize`
alone: the answer sets the rule for every unit in #671–#678.

The state of the rest of the layer decided it. **Every existing spell visual is
already fog-oblivious** — `GlowingDot` bolts fly straight over `FogOverlay`, and
`AllocationVFX` z-promotes to `ZLayers.SPELL_VFX` *specifically* to win over it.

## Decision

**Spell VFX is fog-oblivious, on purpose** — owner call 2026-08-30. New
primitives match the existing ones; nothing in the kit reads the vision field.

This is a decision about **consistency within one layer**, not about hidden
information. Fog withholding is enforced elsewhere; a spell visual is not a
channel the design is trying to close.

## Consequences

- **The layer reads as one thing.** A fog-aware overlay drawing next to
  fog-oblivious bolts is the worse outcome — it looks like a rendering bug, not
  like a rule.
- **Watching an enemy cast into your fog is information you get.** Accepted
  knowingly, and consistent with the wider stance that hidden information in this
  game is social rather than enforced (see
  [ADR 0002](0002-host-authoritative-sync-not-lockstep.md) → *Consequences*).
- **The upgrade stays one line, whenever fog-gating does arrive.** `#include`
  `ui/vision_field.gdshaderinc` and multiply alpha by `vision_field_dim(world_pos)`
  — the reader role #413 designed that file for. Deciding "no" here costs nothing
  later precisely because the mechanism was left in place.
- **It has to be all of them.** If fog-gating arrives it arrives for the whole
  layer at once; a per-spell opt-in would reintroduce the inconsistency this
  decision exists to avoid.

## Alternatives considered

### Make the new primitives fog-aware, leave the old visuals alone

The cheapest thing to type, and the worst result: the kit would then contradict
`GlowingDot` and `AllocationVFX` inside a single cast. Rejected on legibility —
a player cannot tell a deliberate rule from a bug when the same frame does both.

### Make the whole spell-VFX layer fog-aware now

Coherent, and genuinely the alternative with an argument. It lost on cost against
value at the time: it means revisiting every existing spell visual and
`AllocationVFX`'s deliberate z-promotion, in the middle of the kit landing, to buy
a concealment the game does not otherwise enforce. **Not a dead ground** — this is
deferred rather than rejected, and it becomes correct the day hidden information
stops being social.
