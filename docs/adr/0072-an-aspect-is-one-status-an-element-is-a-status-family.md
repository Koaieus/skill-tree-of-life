---
id: 0072
title: An aspect is exactly one status (1:1, test-guarded); an element (Fire, Ice, Lightning) is the only axis that owns a status family, by role — medium, mover, state; Fire is wholly an element and no Explosive aspect survives
status: accepted
date: 2026-11-04
deciders: owner (aspect 1:1, elements own the families, the role table); pass (Poison's second-status idea folds into its one status)
supersedes: []
superseded-by: null
revisit-when: "An aspect genuinely needs a second status that is not an element member"
sources:
  - "#1716"
  - "#1694"
  - "#1733"
  - "#1660"
  - "#1657"
  - "docs/design/elements.md"
  - "aspects/aspect.gd"
tags: [aspects, elements, status, architecture]
---

# ADR 0072 — An aspect is one status; an element is a status family

## Context

`aspects/aspect.gd` holds one `status`; the roster ships thirteen aspects and thirteen `StatusDef`s, `StatusRoster.by_concept` resolves an aspect's status by concept id and `StatusDef._facet_id` is keyed on the concept. #1694 asked (its A1 call, 2026-10-18) to widen `Aspect.status` into a `statuses` array, and the only consumer was Fire needing a second status (Fuel beside Heat). Elements then arrived as a separate axis (#1716): a count on the entity and a short family of statuses on nodes, so the question became where a multi-status concept lives.

## Decision drivers

- **One lookup:** a concept id names exactly one status, so `by_concept`, the facet id and every rider resolve without a pick rule.
- **Readable families:** a multi-status concept is pointed at by role, never as "the fire status".
- **One supply per family:** a family's statuses draw from one count, never two.

## Decision

Owner, 2026-11-04, on re-enforcing Aspect:Status as 1:1 with elements the only axis that owns a status family: *"option 1 sounds very clean"*. On the axes: *"Separate axis sounds good"*; *"elements not being parents of aspects makes sense"*. On the role table: *"that table looks very good, should be persisted"*.

1. **Aspect : Status is 1:1**, as the code already is, and a test guards it (every aspect has one status, no two aspects share one).
2. **Elements — Fire, Ice, Lightning — are the only axis owning a status family**, each member holding a role: **medium** (terrain, side-less, gives reach), **mover** (sided, hurts, spreads), **state** (derived threshold, no count). The members are `docs/design/elements.md` § One count.
3. **Fire is wholly an element.** Fuel is Fire's medium; no Explosive aspect survives.
4. #1694's `Aspect.status → statuses` widening is superseded and unneeded.
5. Pass call (Claude, 2026-11-04): Poison's "does it move" idea (#1657) is a behaviour of the one Poison status, never a second status.

## Consequences

- `by_concept`, `_facet_id` and the rider map stay single-valued; nothing in the aspect pipeline learns about families.
- A concept that needs several statuses must be an element, so it takes the element machinery (one count, roles, reach) whether or not it wants reach.
- Explosive's content (addon, arrow, Firecracker's fuel row) is re-homed under Fire.

## Alternatives considered

### Aspect : Status 1:N (#1694, A1 call of 2026-10-18)
Lost on *one lookup*: every reader of `by_concept` and the facet id would need a pick rule, for one consumer (Fire) that is no longer an aspect. **Most likely to be revived** — by an aspect that wants a second status outside any element; that is the `revisit-when`.

### An Explosive aspect kept beside Fire
Lost on *one supply per family*: two counts (`explosive_aspect`, `fire`) would feed one family (Fuel, Heat), and a build could cap the same Fuel twice. Dead while Fuel is Fire's medium.
