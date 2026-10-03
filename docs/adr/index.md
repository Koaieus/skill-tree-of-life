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
| [0011](0011-one-attack-timeline-contract-for-every-mode.md) | One attack timeline contract for every mode — resolve up front, gate at land time, never re-plan | accepted | 2026-08-20 | combat, attacks, architecture, timing |
| [0012](0012-every-arrow-renders-whatever-it-did.md) | Every arrow renders, whatever the landing did — a render pass never filters on outcome | accepted | 2026-09-04 | combat, attacks, vfx, ranged |
| [0013](0013-host-only-rolls-and-the-seed-is-a-procgen-input.md) | Loot and relic rolls stay host-only, and the run seed is a procgen input rather than a determinism contract | accepted | 2026-08-21 | multiplayer, netcode, determinism, loot, procgen |
| [0014](0014-one-physics-built-defender-field.md) | One physics-built defender field — the solver consumes data, it does not query | accepted | 2026-09-09 | combat, melee, blade, physics, performance, determinism |
| [0015](0015-hidden-information-is-trusted-friends-until-a-competitive-release.md) | Hidden information is trusted-friends until a competitive release; the sync model keeps machine enforcement reachable, and lockstep is closed | accepted | 2026-09-09 | multiplayer, netcode, fog, hidden-information, architecture, melee |
| [0016](0016-a-ratio-contributes-a-line-and-the-stat-floors-once.md) | A ratio intrinsic contributes a line, not a stair; an INT stat floors its finished total once | accepted | 2026-09-14 | stats, balance, loot, formulas, design |
| [0017](0017-combat-quantities-are-int-and-a-merged-read-floors-once.md) | Damage, armor, health, ranges and hop counts are INT stats; a merged (node-local) read floors exactly as a bare one | accepted | 2026-09-15 | stats, balance, combat, design |
| [0018](0018-hit-basis-and-damage-type-are-orthogonal-knobs.md) | A hit's amount basis (flat vs % of max HP) and its mitigation class are orthogonal knobs, authored explicitly — no derived coupling, for now | accepted | 2026-09-16 | combat, attacks, damage, mitigation, architecture, design |
| [0019](0019-ranged-ammo-is-an-entity-level-quiver-not-per-node-stock.md) | Ranged ammo is the entity-board `arrows` PoolStat (the Quiver) with per-type bins, not per-node stock | accepted | 2026-09-18 | ranged, combat, stats, architecture |
| [0020](0020-volley-composition-rides-the-command-typed-along-schedule-order.md) | A ranged volley's composition rides the command as typed counts; per-arrow leaf and type are derived along schedule order at resolve, never carried per arrow or assigned at replay | accepted | 2026-09-18 | ranged, combat, multiplayer, architecture |
| [0021](0021-ranged-reach-is-an-isotropic-disc-and-a-volley-targets-a-node-set.md) | Ranged reach is an isotropic disc and a volley targets a node set — no lanes, cover, or hull geometry | accepted | 2026-09-18 | ranged, combat, procgen, architecture |
| [0022](0022-one-dot-per-defensive-axis-stacks-halve-uncapped.md) | One DoT per defensive axis; a status is uncapped stacks that halve; no per-tick clamp | accepted | 2026-09-20 | combat, status, dot, balance, design |
| [0023](0023-every-notable-stat-gets-an-addon-and-an-arrow.md) | Every notable stat or combo gets a dedicated NodeAddon and an arrow ammo type; every DoT gets both plus spells | accepted | 2026-09-20 | content, addons, ranged, ammo, dot, design |
| [0024](0024-status-effects-have-two-hosts-and-fall-through-a-cracked-core.md) | Status effects have two hosts and fall through a cracked core; presentation composes hosts | accepted | 2026-09-20 | combat, status, architecture, entity, ui |
| [0025](0025-a-default-on-heal-gate-with-an-explicit-raw-bypass-and-a-drift-guard.md) | A default-on heal gate with an explicit raw bypass and a drift guard | accepted | 2026-09-20 | combat, healing, stats, architecture |
| [0026](0026-systems-are-always-present-and-off-is-a-per-system-flag-not-a-base-class.md) | Systems are always present; "off" is a per-system flag, not a null check and not a base class | accepted | 2026-09-21 | architecture, composition-root, systems, scenes |
| [0027](0027-attack-windup-is-an-awaited-presenter-beat-and-the-directors-shot-is-mode-agnostic.md) | An attack windup is an awaited presenter beat behind one contract for every mode, never a schedule offset; the director's shot is mode-agnostic | accepted | 2026-09-21 | combat, presentation, camera, architecture |
| [0028](0028-the-stat-pack-is-the-only-archetype-gate-with-one-universal-pack.md) | A procgen pool rolls where its StatPack says; `&""` on a pack is universal and exactly one pack (`universal.tres`) is | accepted | 2026-09-23 | procgen, content, authoring |
| [0029](0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md) | Related stats compose through declared parents folded in as overlays at read; a quantity is one stat with every bin, never a flat stat plus a multiplier stat | accepted | 2026-09-28 | stats, architecture, authoring, balance, dot |
| [0030](0030-parent-invalidation-propagates-through-the-board-wired-link-not-a-signal.md) | A parent stat invalidates its children through the board-wired link, never through its value_changed signal; parent edges order the batch flush | accepted | 2026-09-28 | stats, architecture, performance |
| [0031](0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md) | Status resistance filters the accumulated float row on the host at each apply and tick, cancelling ⌈row × res − ½⌉ stacks; 100% blocks landing; never a per-hit scale at land | accepted | 2026-09-28 | combat, status, dot, balance, sync |
| [0032](0032-status-stacks-are-integers-a-def-derives-any-fractional-effect-from-the-count.md) | Status stacks are integers — the row stores an int, and a def derives any fractional effect (blindness's %) from the count; no second float field | accepted | 2026-09-30 | combat, status, dot, balance |
| [0033](0033-damage-and-heal-magnitudes-round-up-once-where-produced-mitigation-stays-max-floor.md) | Damage and heal magnitudes round UP once, where the value is produced, so mitigation runs int-on-int; mitigation stays max(min_damage_taken, raw − armor) with negative armor applied before the floor | accepted | 2026-09-30 | combat, balance, stats |
| [0034](0034-armed-input-is-a-statechart-stack-system-whose-attack-level-owns-the-plan.md) | Armed input is a statechart held as a push/pop stack system, a sibling of BattleSystem; levels change only on events, and the attack level owns the in-progress plan | accepted | 2026-09-30 | input, ui, attack, architecture |
| [0035](0035-a-plan-is-seat-local-until-launch-the-host-checks-only-affordability.md) | An attack plan, temp upgrades included, is seat-local until launch; the host judges it once in LaunchAttackCommand and checks only that the player can pay | accepted | 2026-09-30 | multiplayer, sync, attack |
| [0036](0036-a-coreclass-is-a-leaf-reuse-lives-inside-its-typed-arrays.md) | A CoreClass is a leaf that never references another CoreClass; shared parts are file-backed packs and effects dropped into its typed arrays | accepted | 2026-08-04 | entity, core-class, stats, loot, authoring, architecture |
| [0037](0037-territory-selection-is-one-policy-shared-by-spawn-seeding-and-the-ai.md) | Territory selection is one AllocationPolicy, pick_next(entity, candidates, objective), shared by spawn seeding and any AI picker; callers supply candidates and gate, the policy only picks | accepted | 2026-07-21 | ai, procgen, allocation, territory, architecture |
| [0038](0038-int-is-the-runaway-attribute-and-every-int-transfer-is-thinned.md) | INT is the runaway attribute, and every transfer out of it is thinned — spell damage takes √INT, reach and mana take big divisors or saturating ladders; the linear damage payoff and the ×2 reach cap are retired | accepted | 2026-09-21 | stats, balance, int, spells, formulas, design |
| [0039](0039-spell-power-is-gated-by-four-conditions-not-by-damage-tuning.md) | Spell power is gated by four independent conditions — knowing the spell, entity degree at the cast node, mana, range from the cast node — never by tuning damage down | accepted | 2026-08-03 | spells, balance, degree, mana, range, design |
| [0040](0040-statuses-tick-at-the-end-of-the-afflicted-entitys-turn.md) | Statuses tick at the END of the afflicted entity's turn, both hosts in one beat — never at turn start, never per family; a last action before a DoT death is intended | accepted | 2026-09-30 | combat, status, dot, turn, design |
| [0041](0041-special-arrows-bank-outside-the-quiver-capacity.md) | Special arrows bank outside the quiver's capacity, each type under its own `max_stock`; the `arrows` pool's current/max are the plain arrows only (supersedes 0019 in part) | accepted | 2026-10-01 | ranged, combat, stats, architecture |
| [0042](0042-a-save-is-the-join-world-written-to-disk.md) | A save is the join world written to disk; `WorldImage` is the one capture/apply owner, the wire and the disk its transports | accepted | 2026-10-02 | save, multiplayer, netcode, architecture |
| [0043](0043-a-stats-modifiers-are-discrete-obtain-ordered-instances.md) | A stat's modifiers are discrete instances in obtain order: an equal-priority SET clash is an authoring error (last-in wins), a load restores the order, and in game only a formula sum-op fuses | accepted | 2026-10-03 | stats, save-load, multiplayer, loot, architecture |
| [0044](0044-one-on-hit-vocabulary-for-every-attack-mode.md) | One on-hit vocabulary for every attack mode: an `OnHitEffect` reads a mode-agnostic `HitLanding`, and a rider status is gated by the hit it is `paired` with | accepted | 2026-10-03 | combat, on-hit, status, architecture |

## Pre-ADR log

**[legacy-mvp-decisions.md](legacy-mvp-decisions.md)** — the D-1…D-34 log from June–August 2026, written before this tier existed. Same standing as a record: history, never edited. Some D's were later revised or never built, and its crosswalk table says which. Code and docs cite it as `D-N`. When a D turns out to still matter, backfill it as a numbered record (see below) rather than citing the log.

## Reading order

Every ADR is standalone — that is the point of the format — so there is no
required order. If you are new to the tier, read **0001** for what the records
are for, then **0002** as the fullest example of *Alternatives considered* doing
its job: three of its original rejection grounds are recorded as retired, which is
what stops the decision being re-run on a dead argument for a fourth time.

## Backfilling

0002, 0003, 0004 and 0006-0013 are backfills — decisions taken before the tier existed,
extracted from domain docs, a commit message and issue threads. 0006-0013 are the bulk
migration of pre-tier decision prose out of `docs/domain/`, done on **#769**; the
`adr-hygiene` counter it was measured by now reads zero. With that swept,
**backfill on demand, not in sweeps:**
when you find yourself re-deriving why something is the way it is, that is the
signal the decision deserves a record. A backfill says so in a note at the top and
dates itself to the decision, not to the writing.
