# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the filter on the queue**: if something isn't named below, it isn't
scheduled, regardless of its `Ready` column or priority field.

Rewritten 2026-08-03 (second time — see "When this file is wrong"). The 2026-08-03
morning version listed #268 and #274 as "takeable"; both closed that same afternoon.
That kind of drift is exactly what this file exists to stop.

## Why this file exists

The board sprawls. 28 issues in `Ready`, 36 in `Needs design`, 178 open total —
most of it is real work that **does not matter yet**. Design passes kept spawning
issues instead of converging to drone-implementable specs, and `Ready` filled with
things a drone *could* take but nobody *should* prioritize. This file is the antidote:
it names what's actually next, and by omission says everything else is not.

There is one queue for "needs design" work — **#261** (the swarmify pipeline). If an
issue is in `Needs design`, it sits there until a `/swarmify` pass settles its forks
and moves it to `Ready`. **FOCUS does not catalog `Needs design` work** — that's #261's
job, and listing it here is double-counting. FOCUS names only what is past the gate:
drone-ready, files-owned, forks-settled. If it isn't past the gate, it isn't here.

## The rules (unchanged, still load-bearing)

1. **WIP limit: 5 — and it is the weakest rule here.** The real failure mode is
   not too many things `In progress`, it's things *rotting* there: #159, #198,
   #238 and #249 sat in that column for weeks. A swarm that claims ten issues and
   ships them beats three that sit. Judge the column by age, not by count.
2. **One lane at a time.** Lanes below are ordered. Don't open lane N+1 while lane N
   has unfinished scheduled work.
3. **A fork is a Backlog issue, never an immediate start.** When implementing X
   reveals Y: file Y in `Backlog`, finish X, then re-read this file. "It's a small
   thing" is the phrase that has cost the most.
4. **Legibility ships, fidelity defers.** *Does it change what the player can read
   and decide, or how it looks while reading the same thing?* Ship the first; defer
   the second.
5. **Crappy-now beats correct-later for anything not on the critical path.**
6. **`Ready` is a superset, not the queue.** 28 issues sit in `Ready`; most are in no
   lane here. Being `Ready` means "a drone *could* take this"; being named below means
   "a drone *should*".

## Right now — drone-ready and scheduled

Every item below has an acceptance spec, a files-owned list, and forks settled. A
drone takes one and ships it.

| # | What | Why it's the next thing to ship |
|---|---|---|
| **#362** | `test_fan_scene` trace test is run-order dependent | S. Poisons `test:one` for anyone touching fan geometry — i.e. the whole legibility lane. Cheap slot-clearer; do it first. |
| **#286** | AI allocation v1: spend all SP + shallow scoring | The AI banks unspent SP whenever `L < W/5` (every level below 16 at enemy WIS 80). It structurally under-plays. Biggest "game plays itself" gap on the board. |
| **#174** | AI: evaluate melee/magic/ranged every turn, not ranged-only | `AIController._try_attack()` hardcodes `RANGED`. The NPC never considers melee or magic. The stepping stone before #47's strategy controller. |
| **#279** | Enemy CoreClass composability: batch stat/modifier authoring | D-19 puts enemy identity on CoreClass but authoring one `.tres` per enemy duplicates the shared 80%. Blocks content depth. |
| **#337** | Staking mechanics: raise cap with SP+AP, fill, reclaim with extract | The missing combat verb. `SkillPointStat.stake()/extract()` are implemented, the HUD renders the `staked` bucket, the M-of-N dial exists — **nothing in `ui/`, `systems/`, or `entity/` ever calls `stake()`**. Pure wiring. |
| **#340** | Node-local modifiers: bind() + cycle gate at the node seam | A formula-driven node-local modifier silently drops its formula today (`_board == null`). Gates the whole aura lane (D). No design forks left. |

Six units, all drone-ready as written, all gameplay. Take them in lane order below.

## Lanes, in order — ship the playable loop

Lanes are ordered by what makes the game *play*, not by completing subsystems. A
lane is done when its scheduled work ships, not when its topic is exhausted.

### A — The game plays itself (AI)

The biggest needle. The sandbox is a dollhouse until the AI actually spends its
economy and evaluates its options.

1. **#286** AI spends all SP + shallow scoring — drone-ready.
2. **#174** AI evaluates all three attack modes — drone-ready.
3. **#279** Enemy CoreClass authoring architecture — drone-ready.
4. #47 strategy-pattern NPC controller — `Needs design`, lane A's v2. Not this lane's exit.

### B — The missing combat verb

1. **#337** Staking — drone-ready (pure wiring, plumbing exists).
2. #332 node-local formula modifiers scaled off allocation — `Needs design`. Wires onto #340.
3. #301 bladesmithing: spend blade budget on per-swing upgrades — `Needs design`.

### C — Node-local and aura mechanics actually compute

1. **#340** bind() + cycle gate — drone-ready. Without this, node-local formulas are silently inert.
2. #316 heal aura falls off per hop — `Needs design` (D-lane in the old file, folded here).
3. #333 StatFormula can only read a pool cap, not `current` — `Needs design`.
4. #356 unify `PropagationContext` — `Needs design`. Gates #355.

### D — Content comes from the map

1. **#324–#329** procgen v4 draw model (TierLadder + StatPool, spend-until-broke draw, migrate content, debuff pools, consumer sweep) — **six sub-issues, all drone-ready, self-contained.** The single biggest content-shaping block on the board.
2. #330 wire 4 landmark keystone scenes into procgen — `Needs design`.
3. #336 keystone-as-`.tscn` hub — `Needs design`.
4. #206 spell grants in procgen pools — `Needs design`. Lane C in the old file.
5. #207 spell-grant presence viz (flat placeholder emblem) — `Needs design`.

### E — The player can read it (legibility)

Legibility ships, fidelity defers (rule 4). All tooltip-V2 work below is the "show
everything, no gating" phase — flat placeholders, not carved art.

1. Tooltip V2 cluster, drone-ready: **#343** stat slab spec, **#344** holo panel layout inversion, **#345** glass contrast + corner AA, **#234** idle-loop animations, **#236** trace glow, **#281** addon icon placeholder.
2. **#341** RimRing: allocation dial into the shader + archetype legibility — drone-ready.
3. #354 spell preview UI (per-node damage/hit-count chips) — `Needs design`. The preview-scoped RNG snapshot is the open fork.
4. #361 `core_panel.tscn` carries two skins — `Needs design`, blocks nothing but re-bites fan geometry. A *decision*, not a drone unit.

### F — Balance is tuned, not guessed

The harness shipped ( #268, informative-only). #274's spell damage landed. What remains
is the pinning, not the apparatus.

1. #365 mana pool max + regen — `Needs design`, **P0**. Blocks #278: tuning `mana_cost` against placeholder max/regen is tuning against noise.
2. #278 spell balance pass — degree × reach × progression-kind × cost. **A session with the user, not a drone unit.** Runs after #365.
3. #366 harness: magic-channel fixture + `spell_dpa` readout — `Ready`, follow-up to #268 now that #274 landed.
4. #367 harness: wire the seven comment-registered invariants into `invariants.json` — `Ready`. They're prose on an issue today, not numbers.
5. #248 balancing hub (tracking, `Needs design`).

### G — Onboarding (the game teaches itself)

Not scheduled yet — nothing here is drone-ready. Filed so the lane exists:
#300 removable node blockers (teach combat before the first Entity), #49 tutorial.
Both `Needs design`, P0 when scheduled.

## Test coverage cluster (pull in when a lane needs it)

All `Ready`, all sized. Pull one when its lane's work needs the coverage to land safely:
#357 non-melee attack path, #358 the 7 unexercised propagation filters/reducers/steps,
#359 graph layer, #360 integration tier (`Needs design`). #358 is the natural
companion to lane B/C. **#362 (lane E's slot-clearer) is listed up top, not here.**

## Enablers (pull in only when a lane needs them)

- #249 sandbox host live-tab scaffolding — `In progress` (6/12). Reference impl landed; mechanical migration + design-heavy enhancements remain.
- #347 SkillNode lab: `@export_tool_button` entry point, live editor sync, verification readouts — `Ready`. This is the "tweak a value in the editor, see it immediately" tool.
- #349 procgen authoring DX: top-down knobs instead of six-deep nesting — `Ready`.
- #331 harden swarm + drone skills to be harness-independent — `Ready`. Meta, but the swarm orchestrator breaks on opencode without it.

## Deliberately parked

Nothing here is closed. The design survives; the *scheduling* does not — this phase
isn't playing these features, so building them now is stalling dressed as progress.

| Parked | Why |
|---|---|
| #165 pre-authored **clusters** in procgen | planarity + stitching research. Single-node splice (#180/#327/#330/#336) is kept — that one is cheap. |
| #245, #167, #342, #142 emblem/carve substrate + rune art | the Real Attempt. Fidelity, not legibility. Revisit after lane E ships flat versions. |
| #348 addon **placement** UX | wholly undesigned. #337 staking ships without it. |
| #355 Chromatic Cascade | gated on #356 *and* on having played Resonator. |
| #313 ArchetypePolicy clustering dials | overlaps stamping and cluster work. Revisit after procgen v4 lands. |
| #23 pre-authored sandbox content / save-load | metagame; the loop isn't playable end-to-end yet. |
| #256, #257 blade node visual upgrade, "InnerDisk shatter" texture fragmentation | VFX juice. Fun, not load-bearing. |
| #304 retire `BaseCircle` | refactor cleanup. No gameplay consequence. |
| #197 double-crit as a tier | enhancement on working crits. |
| procgen "stamping" | detour; milestone 6 was 8/10 closed. Don't reopen. |

## Known board violations (2026-08-03, evening)

Named, not silently fixed — clearing these is a scheduling decision:

- **Four hubs have been `In progress` for weeks** (#159, #198, #238, #249). #159 is
  19/20 closed — only #234 remains. #238 is 0/1 — only #341 remains. Both close by
  shipping one child each; that is the 2026-08-03 evening swarm's first target.
- **#176 is OPEN but the board says `Done`.** Hygiene flagged it. Close it or move it back.
- **Lane A's `In progress` count was wrong in the prior FOCUS** — it listed 5 incl. #248,
  but #248 sits in `Needs design`, not `In progress`. Corrected here.

Fixed or obsoleted by this rewrite: #268 and #274 were listed as takeable; both closed
2026-08-03 (17:19 and 16:23 respectively). #357–#359 and #362 had no milestone — assigned
in the prior pass. `hygiene` reports the #176 violation above.

## When this file is wrong

It will go stale, like ROADMAP.md did and like the 2026-08-03 morning version did by
the afternoon. That's fine — it's short enough to rewrite in ten minutes. **Rewrite it
rather than patching around it.** The morning version patched #268/#274 in by hand and
was stale within hours; a rewrite would have caught that they'd just closed.