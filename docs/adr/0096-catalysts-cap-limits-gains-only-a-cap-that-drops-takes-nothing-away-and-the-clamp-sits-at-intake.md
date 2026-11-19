---
id: 0096
title: Catalyst's k × T cap limits gains only — a cap that drops takes nothing away and a landing on an over-cap row adds nothing and removes nothing; the clamp sits at intake on the status host, never as a trim of a standing row — refines 0081 §6
status: accepted
date: 2026-11-19
deciders: owner (the cap limits gains only); pass (the clamp at intake through a per-host cap the def supplies, the trim hook and its restore exception going)
supersedes: []
superseded-by: null
revisit-when: "a status needs a cap that takes stacks away when it drops, an over-cap store proves too strong to leave standing, or building the intake clamp turns up a reason to keep the restore hook (the tentative pass picks)"
sources:
  - "#1830"
  - "#1801"
  - "docs/handoffs/owner-forks-2026-11-18.md"
  - "docs/domain/catalyst.md"
  - "effects/status/catalyst.gd"
  - "combat/status_host.gd"
  - "docs/adr/0081-a-go-off-pays-one-per-node-reached-catalyst-replaces-fuel-and-a-cast-carries-one-element.md"
tags: [combat, status, elements, catalyst, sync, architecture]
---

# ADR 0096 — Catalyst's cap limits gains only

## Context
ADR 0081 §6 caps Catalyst's row at its node's k × T (a pass pick; k = 2 + stake level, T = 2 × graph degree) and says nothing about a cap that moves. It does move: a gate flip that removes an incident edge takes T down by 2, a stake extract takes k down by 1. At c1a8557 the status host bounds a write at `StatusDef.power_max` only (Catalyst's is 0, none), and `CatalystStatus._on_applied` trims the row back to the cap after every landing or move. So a dropped cap left the row alone until the next landing, which then cut it: +2 on a row of 18 under a cap of 12 left 12. A snapshot or save restore had to skip that trim through a no-op `_on_restored` override, the only override of that virtual, or a restored peer would hold a different row than the authority sent. No ADR says where a status cap is enforced.

## Decision drivers
The owner picked an option and gave no grounds; these are the pass's.
- **A landing is predictable from the row and the cap in front of it**: what it does never depends on what happened to the cap earlier.
- **A restore is the authority's row as sent**: no rule re-derives a row on a peer.
- **One door for a clamp**: the status host already bounds every write; a second bound on the def, after the fact, is a parallel one.

## Decision
1. **The cap limits gains only** (owner, 2026-11-19, picked *the cap limits gains only*): a cap that drops takes nothing away, and a landing on an over-cap node adds nothing and removes nothing.
2. **The clamp sits at intake** (pass, tentative): the def supplies a per-host cap (0 = none; Catalyst's is its node's k × T) and the status host bounds a write that raises a row, `next = min(target, max(before, cap))`. A reduction and a restore are written as sent. `CatalystStatus._on_applied`'s trim goes, and with it the reason `_on_restored` exists.

**Stands:** the cap's value (0081 §6) and the Heat / Cold / Charge overflow band (ADR 0075 §7), which is terrain, not a status row.

## Consequences
- A row over its cap is a legal state; only a conversion, decay or a removal brings it down. A gate flip or a stake extract never destroys crystals.
- An over-cap node is closed to Catalyst gains until its row falls under the cap, whatever the door: a landing, the barrel's top-up, a status move.
- A restore needs no exception: nothing trims a standing row.
- The cost: k × T no longer bounds what a node can hold, so a conversion can release more than the cap in front of the player suggests; and every raising write pays one cap read on the host.

## Alternatives considered
The option list put to the owner on 2026-11-19 is not in the repo; the first two are the readings the forks file posed (*"Re-trim on the drop, or keep?"*).
### Re-trim on the drop
The row is cut to the new cap the moment the cap falls. Lost on *a restore is the authority's row as sent* turned around: the trim is a world mutation every peer must reproduce at the flip or the extract, and closing a gate deletes crystals. **Most likely to be revived**, if a store standing over its cap proves too strong.
### Keep the trim at the next landing (as built)
Lost on *a landing is predictable*: a +2 landing removes 6, and the restore path needs its exception.
### A gain-aware trim on the def
Keep `_on_applied` and have it compare before and after. Lost on *one door for a clamp*; the hook's own comment said a per-host cap on the host would replace it.
