---
id: 0051
title: A ranged volley rides the command as an ordered `[{type, count}]` list in the player's card order; per-arrow leaf and type are still derived along schedule order at resolve — supersedes 0020
status: accepted
date: 2026-10-09
deciders: owner (the list shape and the supersession); agent (drafting)
supersedes: [0020]
superseded-by: null
revisit-when: null
sources:
  - "#1512"
  - "#1270"
  - "docs/domain/attack-timeline.md"
tags: [ranged, combat, multiplayer, architecture]
---

# ADR 0051 — A ranged volley rides the command as an ordered `[{type, count}]` list in the player's card order

## Context

ADR 0020 put the volley on the wire as `ammo_counts: {type_id: n}` and assigned
types along schedule order in the roster's fixed `AmmoType.order`; ADR 0019
(lines 83-84) likewise read composition as "typed counts in a fixed roster
order" — a line this record overtakes. The #1270 ranged-body redesign gives each entity a run-sticky card
order (`VolleyPreference.order`, seat-side per #1511), and the owner wants that
order to be the firing order — which a dict keyed by type cannot carry.

## Decision drivers

- A mirror reproduces the volley from the command alone (ADR 0002); nothing per arrow crosses the wire.
- The order a player sets is the order arrows land, and it must survive the wire.
- One source of truth for order: the plan, not the roster, once a player has chosen.

## Decision

The plan's volley is `RangedAttackPlan.ammo: Array[Dictionary]`, entries
`{type, count}` in firing order, one entry per type. Owner, 2026-10-09: *"isn't
the realio dealio of what's being sent like [{type:armor-breaking, count:3},
{type:normal, count: 123}, …]. a literal array already ordered"*; on ADR 0020:
*"supersede it"*. The order comes from `VolleyPreference.order`; an empty order
is `AmmoTypeRoster.sorted()` (authored `AmmoType.order`). Everything else in
0020 stands: wave-major schedule, types assigned along schedule order at
resolve (now walking the list), consumption at commit from the rebuilt command.

## Consequences

- The firing order is wire state; a mirror fires the authority's order without knowing anyone's preference.
- `validate` refuses a duplicate type, so "one position per type" is enforced at the plan, not only in the UI.
- An AI with no card order sends the roster's order; adding an ammo type still never touches the wire format.

## Alternatives considered

### Keep `{type: n}` and send the order alongside
Two fields that must agree, and the dict's own key order invites a reader to trust it. Lost on "one source of truth".

### Ordered bands (split piles of one type)
0020's rejected maximal form; the owner reopened it only in the milder one-position-per-type form. Most likely to be revived — a revival supersedes this record and drops `validate`'s duplicate refusal.

### Fixed roster order (0020)
Lost on "the order a player sets is the order arrows land".
