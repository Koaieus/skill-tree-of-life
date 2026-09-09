# Architecture Decision Records

**Why we chose this over that, on this date, knowing what we knew.** Each record
is written once and never edited; when a decision changes, a new record supersedes
it and the old one keeps its original text.

The convention — the boundary against `docs/domain/`, the template, how to
supersede — is **[docs/domain/adr.md](../domain/adr.md)**. The tier establishes
itself in **[ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)**,
which is also the worked example of the format.

**Before re-arguing anything listed below, read its *Alternatives considered*
section.** Several of these decisions have already been re-litigated once, and the
grounds that are *dead* are recorded as dead precisely so nobody picks one up
again.

```
mise run adr-hygiene     # frontmatter, supersede links, index coverage, immutability
```

## Records

| # | Decision | Status | Decided | Tags |
|---|---|---|---|---|
| [0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md) | ADRs record decisions; domain docs record behaviour | accepted | 2026-09-07 | meta, documentation |
| [0002](0002-host-authoritative-sync-not-lockstep.md) | Host-authoritative intent-up / confirmed-command-down, not lockstep on a shared seed | accepted | 2026-08-24 | multiplayer, netcode, architecture |
| [0003](0003-the-entry-point-is-config-not-an-autoload-redirect.md) | The entry point is a config setting, not an autoload redirect | accepted | 2026-09-01 | boot, scenes, exporting |
| [0004](0004-the-allocation-level-magnitude-ladder-is-linear.md) | The allocation-level magnitude ladder is linear | accepted | 2026-08-05 | stats, balance, skill-node, design |
| [0005](0005-blade-parts-and-counters-are-orthogonal.md) | Blade parts and their counters are orthogonal — bunkers destroy structure, never matter | accepted | 2026-09-08 | combat, melee, blade, design, balance |
| [0006](0006-unreferenced-art-is-deleted-and-re-cut-not-excluded.md) | Unreferenced purchased art is deleted and re-cut from a pipeline, not excluded from the export | accepted | 2026-09-04 | exporting, assets, build |
| [0007](0007-spell-vfx-is-fog-oblivious.md) | Spell VFX is fog-oblivious — every spell visual draws over fog, or none does | accepted | 2026-08-30 | vfx, spells, fog, rendering |
| [0008](0008-a-growth-capped-npc-breaks-out-through-a-bordering-door.md) | A growth-capped NPC breaks out through a bordering door, at every AI tier | accepted | 2026-08-26 | ai, dormant-core, allocation, balance |
| [0009](0009-the-victory-condition-is-a-swappable-resource.md) | The victory condition is a swappable resource; last-camp-standing is the first, not the only one | accepted | 2026-08-21 | victory, session, architecture |
| [0010](0010-contest-membership-is-a-rule-the-condition-owns.md) | Contest membership is a predicate the victory condition owns, not a flag on Faction | accepted | 2026-08-22 | victory, session, architecture, entity |

## Reading order

Every ADR is standalone — that is the point of the format — so there is no
required order. If you are new to the tier, read **0001** for what the records
are for, then **0002** as the fullest example of *Alternatives considered* doing
its job: three of its original rejection grounds are recorded as retired, which is
what stops the decision being re-run on a dead argument for a fourth time.

## Backfilling

0002, 0003 and 0004 are backfills — decisions taken before the tier existed, extracted
from a domain doc, a commit message and an issue thread respectively. The bulk migration of decision prose that predates the tier is tracked on **#769**, whose acceptance is the `adr-hygiene` counter reaching zero. Outside that, **backfill on demand, not in sweeps:**
when you find yourself re-deriving why something is the way it is, that is the
signal the decision deserves a record. A backfill says so in a note at the top and
dates itself to the decision, not to the writing.
