---
id: 0050
title: Special arrows mint from the concept's `<concept>_aspect` stat; the per-type `<id>_arrows_per_reload` stat is retired — supersedes 0023's reload clause
status: accepted
date: 2026-10-08
deciders: owner (the supersession, 2026-10-05 sweep); agent (drafting)
supersedes: [0023]
superseded-by: null
revisit-when: null
sources:
  - "#1414"
  - "#1248"
  - "docs/adr/0041-special-arrows-bank-outside-the-quiver-capacity.md"
  - "docs/adr/0044-one-on-hit-vocabulary-for-every-attack-mode.md"
  - "attack/ammo/ammo_type.gd"
tags: [combat, ammo, stats]
---

# ADR 0050 — Special arrows mint from `<concept>_aspect`

## Context

ADR 0023 required every fun stat's arrow type to carry its own `<id>_arrows_per_reload` stat. #1248 settled supply as *mint on reload* from the concept's `<concept>_aspect` count, and ADRs 0041 and 0044 built on that (`AmmoType.per_reload_stat_id` names the minting stat, which is the aspect). 0023 stayed `accepted` with its per-type clause standing, contradicting the code.

## Decision

Owner's sweep finding, 2026-10-05 (#1414): 0023's per-type reload clause is stale. A special arrow type mints per reload from its concept's `<concept>_aspect`; no `<id>_arrows_per_reload` stat exists. 0023's other clauses (a dedicated NodeAddon per notable stat, an arrow per fun stat, three faces per DoT member) are unchanged and still stand.

## Consequences

- 0023 is marked superseded for its reload clause only; read it for the addon and spell rules.
- A new arrow type authors `per_reload_stat_id` as an aspect stat, never a bespoke reload stat.

## Alternatives considered

### Keep a per-type reload stat beside the aspect
Loses to #1248: two numbers for one concept, and melee and magic would need their own "poison arrows" stat. Dead.
