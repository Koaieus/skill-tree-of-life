---
id: 0023
title: Every notable stat or stat combo gets a dedicated NodeAddon and an arrow ammo type; every DoT gets both plus spells
status: accepted
date: 2026-09-20
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#952"
  - "#951"
  - "docs/design/damage_over_time.md"
  - "docs/design/skill_node_addons.md"
  - "attack/ammo/ammo_type_roster.tres"
tags: [content, addons, ranged, ammo, dot, design]
---

# ADR 0023 — Every notable stat or stat combo gets a dedicated NodeAddon and an arrow ammo type

## Context

Content has grown one item at a time: Bunker (armour + floor), Spikes (blade
damage), Watchtower (ranged damage + vision), poison arrows. Each was argued
on its own. The #952 session made the pattern explicit when the DoT family
needed sources: nothing applied corruption, curse or wither, and melee had no
poison at all (#951).

## Decision

Owner, 2026-09-20: *"arrow ammo type for any fun stat; at least 1 dedicated
NodeAddon for every cool stat or combo of stats."*

- **Every notable stat, or combination of stats, has at least one dedicated
  `NodeAddon`** that grants it, with a blade-copy face where melee can carry
  it (the #951 shape).
- **Every fun stat has an arrow ammo type** (`attack/ammo/types/`, its own
  `<id>_arrows_per_reload` stat, a roster entry).
- **Every DoT family member has all three: an arrow, an addon, and one to two
  spells** — *"whichever creates fun gameplay and build variety."*

Missing one of these for a shipped stat is a content gap to file, not a
design question to reopen.

## Consequences

- Filing a new stat implies filing its addon and arrow (and spells if it is a
  DoT) as siblings; #971–#973 are the first instances.
- Addon and ammo rosters grow linearly with the stat roster; per
  `docs/design/skill_node_addons.md` the addon roster stays procgen-weighted,
  so completeness does not mean equal frequency.

## Alternatives considered

### Author content only where a build asks for it
**Rejected.** That is how three DoTs ended up with no source; the gap is only visible once the rule is stated.
