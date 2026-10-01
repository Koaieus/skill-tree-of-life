---
id: 0041
title: Special arrows bank outside the quiver's capacity, each type in its own bin under its own max_stock; the arrows pool's current/max are the plain arrows only
status: accepted
date: 2026-10-01
deciders: owner
supersedes: [0019]
superseded-by: null
revisit-when: null
sources:
  - "#1248"
  - "#1267"
  - "docs/adr/0019-ranged-ammo-is-an-entity-level-quiver-not-per-node-stock.md"
  - "stats_system/quiver.gd"
  - "attack/ammo/ammo_type.gd"
tags: [ranged, combat, stats, architecture]
---

# ADR 0041 — Special arrows bank outside the quiver's capacity, each under its own max_stock

> **Supersedes ADR 0019 in part**: only its *"current = total stock, max = quiver capacity"* with the bins *inside* current. Everything else in 0019 stands — the entity-level `Quiver` that IS the `arrows` stat, per-type bins behind `stock_of / add / take`, reload minting, the per-leaf shot budget. 0019 therefore stays `accepted`.

## Context

#1248 settled special-arrow supply as *mint on reload*: each reload grants the full `<concept>_aspect` count of that type. Under 0019 every bin sat inside one shared capacity (default 40), so a build that minted specials every reload filled the quiver with them and crowded out its own plain arrows — and banking specials across turns, which the owner wanted, would make that worse with every turn.

## Decision drivers

- A special build must never cost its plain arrows (the shared-cap crowd-out).
- Specials bank across reloads, but stay bounded.
- The wire shape and the entity-level quiver of 0019 stay as they are.
- `stats_system/` sits below `attack/`: the stat cannot read the `AmmoType` roster.

## Decision

Owner, 2026-10-01 (#1248): *"Banks, capped at 999 per type."* — and, offered the choice, the owner picked **"Specials leave the shared cap"**.

- The `arrows` pool's `current` / `max` are the **plain (base) bin** against quiver capacity: `current == bins[BASE_ID]`.
- Each special type banks in its own bin beside `current`, clamped to `AmmoType.max_stock` (default 999, owner-tunable per type). A capacity change never touches a special; a falling capacity trims the plain bin only.
- The cap reaches `Quiver` as an argument from the caller (`add(type_id, n, max_stock)`); `Quiver` never reads the roster and keeps its own `BASE_ID`, pinned equal to the roster's by test.
- Readers choose their meaning: "what can a volley draw on" is every bin (`Quiver.total_stock()`); "is a reload worth the AP" is whether any minted bin has room.
- `to_dict` / `read_dict` carry every bin; the wire shape is unchanged.

## Consequences

- A poison or scout build keeps its full plain capacity; specials accumulate up to their own cap.
- `current` no longer means "arrows held". Any reader that wants the total must call `total_stock()`, and one that reads `current` gets the plain arrows only.
- The stock a volley can draw on is no longer bounded by capacity, only by `max_n`'s shots-left term and each special's cap.
- `Quiver.BASE_ID` duplicates `AmmoTypeRoster.BASE_ID`; a test is what keeps them equal.

## Alternatives considered

### Keep the shared cap (0019 as written)
Simplest, and it was the shipped shape. It lost on the crowd-out driver: minted specials displace plain arrows, worse with banking. **Most likely to be revived** if specials ever become rare enough that crowding stops mattering.

### Specials not banked (consumed or lost at turn end)
Rejected by the owner's *"Banks"*: a reload that mints specials should build up a stock.

### `Quiver` reads each type's cap from the roster
One fewer argument per call, but it would be an upward dependency from `stats_system/` into `attack/`, which the module rules forbid.
