---
id: 0013
title: Loot and relic rolls stay host-only, and the run seed is a procgen input rather than a determinism contract
status: accepted
date: 2026-08-21
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#509"
  - "#457"
  - "#473"
  - "#715"
  - "docs/domain/multiplayer-sync-model.md"
tags: [multiplayer, netcode, determinism, loot, procgen]
---

# ADR 0013 — Host-only rolls, and the seed as a procgen input

> **Backfilled 2026-09-07** from `docs/domain/multiplayer-sync-model.md`, which
> recorded this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

Before 2026-08-21 the working rule in `multiplayer-sync-model.md` was absolute:

> *"`Array.shuffle()` with no argument is a desync. Every gameplay-affecting roll
> draws from a `GameSession` sub-stream."*

Under that rule the unseeded global shuffles in `systems/loot_system.gd` and
`skill_node/addons/skill_dust_addon.gd` were outstanding cleanup work, and the
#457 `GameSession` seed was implicitly a cross-peer determinism contract over
everything it touched.

The question put to the owner was whether that rule had to hold for *loot*, given
that a loot round is performed by one player, out of a candidate list the receiver
already has, and is invisible to everyone else while it happens.

## Decision

**A roll whose *result* crosses the wire needs no reproducibility. Only the pick
travels.**

> **Owner call 2026-08-21:** *"loot picks are just 'hey i picked <this
> statmodifier>', users cannot distinguish a same-seed roll from a random roll
> given that looting is done by 1 player and invisible to others — the resulting
> pick however needs to be communicated back to host so they can broadcast or
> whatever if needed"*

And on the scope of the run seed:

> **Owner call 2026-08-21:** *"we don't care about that seed beyond the procgen
> using it, for now. possibly forever."*

So the pick command carries `(entity_id, request_id, chosen_indices)` and nothing
more (#509), the host's unseeded shuffles are legal, and **the same seed
reproduces the same map, not the same fights.**

The narrower rule that survives: *if a result crosses the wire as something a peer
re-derives rather than receives, it draws from the seed it was handed.* What
changed is the **scope** — host-only rolls are exempt, because nothing re-derives
them.

## Consequences

- **A whole class of would-be cleanup work was retired**, not deferred. The
  unseeded `Array.shuffle()` calls are correct as they stand.
- **It removed one of the three grounds** the lockstep rejection originally rested
  on — recorded as dead in
  [ADR 0002](0002-host-authoritative-sync-not-lockstep.md), which was decided three
  days later on entirely different premises.
- **Combat reproducibility became a per-attack stamp instead of a run-level
  stream.** `launch_attack` stamps `attack_plan.resolve_seed` before resolving and
  `outcome.resolve_seed` carries it back out (`8dc6f77`), so a peer can verify by
  re-resolving.
- **Since #715 the seed is not a cross-peer contract at all.** It reproduces a map
  *on one machine* — a replay input. Only the host generates; a joining client
  receives the authority's serialized graph and never runs `GraphProcgen`. That is
  what takes `procgen/`'s transcendentals (#547, #689, #706 — `pow()` in the seeded
  draw, whose last bit is not portable across two platforms' libm) off the LAN
  critical path entirely.

## Alternatives considered

### Seed every gameplay roll from a `GameSession` sub-stream

The rule as originally written, and **superseded rather than merely relaxed**. It
is the right rule for anything a peer re-derives; it was being applied to rolls no
peer re-derives, where it buys a property no player can observe. Its cost was real:
threading a sub-stream through the loot system and the dust addon, plus a standing
obligation on every future roll.

### Ship the loot roll and let each peer reproduce the pick

The lockstep-shaped answer. It requires the candidate ordering to be portable
across platforms and buys nothing — the owner's point is that a same-seed roll and
a random roll are *indistinguishable to a user* when one player is looting and the
result is what gets broadcast.
