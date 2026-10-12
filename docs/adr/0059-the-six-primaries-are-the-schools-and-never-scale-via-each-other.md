---
id: 0059
title: The six primary attributes are the schools, and a primary never scales via another primary
status: accepted
date: 2026-10-05
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "a core class or keystone makes one primary count as another (\"STR counts for INT\")"
sources:
  - "#1431"
  - "#1249"
  - "#1199"
  - "docs/design/aspect_matrix.md"
  - "docs/adr/0038-int-is-the-runaway-attribute-and-every-int-transfer-is-thinned.md"
  - "entity/default_entity_board.tres"
  - "test/unit/stats/test_primaries_never_scale_via_primaries.gd"
tags: [stats, attributes, schools, aspects, design]
---

# ADR 0059 — The six primaries are the schools, and never scale via each other

> **Backfill.** The owner settled both rules on 2026-10-05 (`docs/design/aspect_matrix.md` § Schools); the `/swarmify` pass of 2026-10-12 ratified them as an ADR (#1431). Dated to the decision, not the writing.

## Context

The aspect matrix needs a grouping that makes a spell's aspects legible and ties them to a build choice. The six primary attributes (STR, DEX, INT, WIS, PER, CON) already exist, already root the stat tree (every primary has `parent_ids = [attributes]`), and every intrinsic link on `entity/default_entity_board.tres` already runs primary → non-primary. The question was whether to add a separate school concept, and whether primaries may feed each other.

## Decision drivers

- **No second taxonomy:** a school should be something the player already invests in.
- **Attributes stay roots:** a primary's value must be a pure allocation outcome, so builds stay readable.
- **No free scaling:** an aspect must not scale with a stat just by being thematically near it.

## Decision

**The six primary attributes are the schools** (owner, 2026-10-05: *"i think the 6 primary attributes serving as schools is the way to go about this"*), and **a primary never scales via another primary** (owner, 2026-10-05): primaries *"generally never scale via other primaries"* and *"may be used as scaling base for other stats, not the other way around"*.

- A stat link whose target is a primary never has another primary as its source. Primary → non-primary links are the normal case (`blade_size` takes a STR-dependent addition; ADR 0038 governs the INT ones).
- An attribute does not *own* an aspect: *"attribut doesn't own the aspect but we design them to mostly fit one, thematically or logically, which is a somewhat loose coupling"* (owner, 2026-10-12). So `Archetype` carries no `aspects` list; the fit is a design-time mapping, not a structural field (rejects #1249 option A).
- Supporting line (owner, 2026-09-28, #1199): *"we surely don't want to scale these effects innately with those stats for free"*.
- The rule is enforced by `test/unit/stats/test_primaries_never_scale_via_primaries.gd`, which discovers the primaries from the defs (the children of `attributes`) and scans the shipped boards. The guard test is the speccing session's tentative pick.

## Consequences

- A new primary needs only `parent_ids = [attributes]`; the guard picks it up.
- A board authoring `STR → INT` fails the suite, not a playtest.
- Which attribute fits which aspect stays an open design mapping (#1249), free to change without a schema change.
- Revisit when a core class or keystone deliberately makes one primary count as another; that content would need an explicit exemption in the guard.

## Alternatives considered

### A separate school entity
**Rejected on no-second-taxonomy.** A new concept the player does not invest in duplicates what the primaries already express.

### `Archetype.aspects` list (#1249 option A)
**Rejected by the owner, 2026-10-12**, on the loose-coupling quote above: a structural field turns a thematic fit into a rule, and invites free innate scaling. *The alternative most likely to be revived* by someone wanting a queryable attribute → aspect table; build a design-doc table instead.

### Allow primary-to-primary scaling
**Rejected on attributes-stay-roots.** Chains such as STR → INT make a primary's value depend on allocation elsewhere and blur which school a build invests in.
