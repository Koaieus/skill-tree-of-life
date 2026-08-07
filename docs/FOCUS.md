# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the filter on the queue**: if something isn't named below, it isn't
scheduled, regardless of its `Ready` column or priority field.

Rewritten 2026-08-03 (second time — see "When this file is wrong"). The 2026-08-03
morning version listed #268 and #274 as "takeable"; both closed that same afternoon.
That kind of drift is exactly what this file exists to stop.

Patched 2026-08-05: the AI lane's drone-ready entries #286 + #174 superseded by the
design-pass hub #378 (fog-aware tactical loop, MCMC melee, tiered scoring). The two
units closed as folded-in; their scope is a strict subset of #378's spec. Net Ready
count: -1 (#286, #174 closed; #378 filed).

Patched 2026-08-07: **#384 + #385 inserted at the head of lane A, ahead of #378.**
Both came out of #383's design pass and both are #378 prerequisites, not adjacent
work. #384 is the sharper one: with no faction concept, "hostile" is computed as
`owned_by != attacker`, so **every AI entity currently reads every other AI entity
as an enemy** — #378's per-candidate EV would happily score enemies attacking each
other. #385 is the enumeration API #378's scoring needs (`Targeting.valid_targets`
today has zero callers and runs one AStar query per node). Net Ready count: +2.

Rewritten-in-place 2026-08-07 (lane order): **the glowup is lane A and the AI lane
moves to last.** #371's bloom foundation landed, which turned nine "make this glow"
bullets into seven `Ready`, file-disjoint units that can all be judged against a real
pass. This is a deliberate call that how the game *looks* is what's blocking right
now — it costs #378 its head-of-queue position, and rule 2 means the AI lane does not
open until the glowup's scheduled work ships.

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
| **#389** | RimRing lit-slot arcs bloom at the alert tier | Lane A's payoff. #371's pass is live and the SDR baseline was pre-darkened for exactly this; the arcs are the one thing meant to punch through. |
| **#388** | Edge lit state emissive, not an additive underlay | The "Temu glow" — a `Line2D` underlay at `glow_alpha_lit = 0.4`, alpha-as-dimmer, which the pass makes unnecessary. With #389, the whole "graph looks alive" read. |
| **#392** | Emissive pass over attack + allocation VFX | Projectiles, blades, modifier-to-core particles, loot-node sparkle. File-disjoint from #388/#389 — swarms alongside them. |
| **#390** | HUD text onto emissive tiers + panel borders | Sweeps the clusters onto `Tier*` variations. Discipline: most of the HUD stays inert or bloom stops meaning "state changed". |
| **#236** | Tooltip V2: trace glow shader polish | Moved out of lane E — it is glow work, judged best next to the rest of it. |
| **#393** | Strikethrough toast laser-cut trace glows | S. The trace can be a laser now instead of a bright line. |
| **#391** | `fused_panel` `glow_energy` + instance uniforms | **Deferrable indefinitely.** Consistency refactor, not a glow blocker; the one #371 path that was reasoned rather than probed. |
| **#362** | `test_fan_scene` trace test is run-order dependent | S. Poisons `test:one` for anyone touching fan geometry — i.e. the whole legibility lane. Cheap slot-clearer; do it first. |
| **#384** | Ownership buckets Neutral/Mine/Ally/Hostile + `Entity.attitude_to` + `Faction` | **Blocks #378.** Without it "hostile" is `owned_by != attacker`, so every AI entity reads every other AI entity as an enemy. Also folds in #386's whole scope (closed): XP is killer-attributed and gated on hostility, one guard in `LootSystem`. Two teams, forks settled 2026-08-07. |
| **#385** | Set-shaped targeting: gather the reachable set once, not `in_range` per node | **Blocks #378** (ranged + magic scoring; melee enumerates by blade-shape search instead). Its scoring needs candidate enumeration; `Targeting.valid_targets` has zero callers today and the live path runs one AStar query *per node per repaint*. Verified pure perf — `AStarSkillTree` costs edges flat, so BFS and `get_id_path` agree. |
| **#378** | AI controller v1: fog-aware tactical loop + MCMC melee + tiered scoring | Lane H's v1, design-pass settled 2026-08-05. Supersedes #286 + #174 (both closed as folded-in). Recon (fog short-circuit) → tactical SP-growth (recon-pulled near-miss-enable) → AP×2 attacks with per-candidate EV across all three modes (ranged/magic enumerable, melee = MCMC blade rollouts on WorkerThreadPool — the multicore crunch) → end turn. Tier-gated scorer (`ai_tier: int`). `Events.ai_decision` signal always-emitted + `debug_trace` print toggle. Shape-locked v1 (DP=0, movement=0). Single biggest "game plays itself" gap on the board. |
| ~~**#286**~~ | ~~AI allocation v1: spend all SP + shallow scoring~~ | **CLOSED.** Superseded by #378 — scope absorbed into tactical SP-growth steps. |
| ~~**#174**~~ | ~~AI: evaluate melee/magic/ranged every turn~~ | **CLOSED.** Superseded by #378 — scope absorbed into AP×2 attack enumeration with per-candidate EV. |
| ~~**#279**~~ | ~~Enemy CoreClass composability: batch stat/modifier authoring~~ | **CLOSED.** |
| **#337** | Staking mechanics: raise cap with SP+AP, fill, reclaim with extract | The missing combat verb. `SkillPointStat.stake()/extract()` are implemented, the HUD renders the `staked` bucket, the M-of-N dial exists — **nothing in `ui/`, `systems/`, or `entity/` ever calls `stake()`**. Pure wiring. |
| ~~**#340**~~ | ~~Node-local modifiers: bind() + cycle gate at the node seam~~ | **CLOSED.** Lane D's aura work unblocked. |
| **#374** | stake_level as PoolStat + proxy props on SkillNode | Mechanism layer of #332's "we want both" design — cap = stake_level, current = allocation_level, authored via SkillNode-scope proxy properties. Depends only on closed/Ready work (#333, #340, #337). Zero forks. |
| **#375** | `addon_slots = base(0) + allocation_level` as a node-local Stat | First consumer of the node-local scaling plumbing. Reads `allocation_level` through the `stake_level__current` accessor (#333). Depends on #374. |
| **#376** | Magnitude curve: linear-ladder mutator on SkillNode | The design heart of #332. SkillNode owns its modifiers, entity board holds references, a mutator runs once per al-change writing `value` in place. Linear ladder (`return float(al)`), plug-and-play body. MULTIPLY scales "add the growth part" (`1 + (X−1)×ladder`); SET opts out by default. Composition mutation covered (the "1→2 effects" case). Single-owner-SkillNode precondition asserted; **#377** is the long-term escape. |

Fifteen units, all drone-ready as written. Take them in lane order below — **the glowup is
lane A now, and the AI lane is last**; rule 2 means #384/#385/#378 do not open until
lane A's scheduled work (#389, #388, #392) ships.

## Lanes, in order — ship the playable loop

Lanes are ordered by what makes the game *play*, not by completing subsystems. A
lane is done when its scheduled work ships, not when its topic is exhausted.

### A — The glowup (emissive everything)

#371's bloom pass is live, so every one of these can be judged against real light
instead of guessed at. They are file-disjoint from each other — this lane swarms.

> **Blocker on the judging surface, 2026-08-07:** the sandbox host's **Bloom** tab
> shows no bloom *in the editor* and its sliders are inert (diagnosis on #371;
> #371 is back to `In progress`). The pass itself is verified working in a running
> game — this is a tab/editor problem, not an Environment problem, so **don't
> retune `default_game_env.tres` chasing it.** Until it's fixed, judge glow work by
> running `scenes/procgen_play_sandbox.tscn`, not in the editor.

1. **#389** RimRing lit-slot arcs at the alert tier — **Ready.** *The* payoff. The
   SDR baseline was already darkened so the unallocated node reads right without
   glow; these arcs are the one thing meant to punch through. Take it first even
   though its own breadcrumb says "last" — that meant last *within #371*, and #371
   is done.
2. **#388** Edge lit state emissive — **Ready.** The "Temu glow": a wider `Line2D`
   underlay at `glow_alpha_lit = 0.4`, i.e. alpha used as a dimmer, which is exactly
   what the pass makes unnecessary. Together with #389 this is the whole "the graph
   looks alive" read.
3. **#392** attack + allocation VFX emissive pass — **Ready.** Projectiles, blades,
   modifier-to-core particles, and the new loot-node sparkle.
4. **#390** HUD text onto tiers + panel borders — **Ready.** Sweeps the clusters onto
   `TierLabel`/`TierValue`/`TierAlert`. Discipline work: most of the HUD must stay
   inert, or bloom stops meaning "state changed".
5. **#236** fan trace glow — **Ready.** Kept its own issue rather than folding into
   #371; the tip can now actually glow.
6. **#393** strikethrough toast laser-cut trace — **Ready.** Small.
7. **#391** `fused_panel` `glow_energy` + instance uniforms — **Ready**, and
   **deferrable indefinitely.** A consistency refactor, not a glow blocker; the one
   path in #371 that was reasoned rather than probed.

Gated behind #261, not scheduled here (FOCUS doesn't catalog `Needs design`):
**#140** aura fields span edges, **#257** node-shatter texture fragmentation. Both
have been told the foundation is live.

Lane exit: #389 + #388 + #392 shipped. The rest is polish that can trail.

### B — The missing combat verb

1. **#337** Staking — drone-ready (pure wiring, plumbing exists). Sibling: #338 (player-facing surface, `Needs design`).
2. **#332** node-local formula modifiers — hub, `Needs design` until its children land. Swarmify 2026-08-05 split out three children:
   - **#374** stake_level as PoolStat + proxy props — **Ready.**
   - **#375** `addon_slots = base(0) + allocation_level` as node-local Stat — **Ready.** Depends on #374.
   - **#376** magnitude curve linear-ladder mutator on SkillNode — **Ready.** Depends on #374 + #337.
3. #301 bladesmithing: spend blade budget on per-swing upgrades — `Needs design`.

### C — Node-local and aura mechanics actually compute

1. ~~**#340** bind() + cycle gate at the node seam — drone-ready.~~ **CLOSED.** Lane B's children build on this.
2. #316 heal aura falls off per hop — `Needs design` (D-lane in the old file, folded here).
3. ~~#333 StatFormula accessor for `__current`~~ **CLOSED.** Lane B's children read `allocation_level` through this.
4. #356 unify `PropagationContext` — `Needs design`. Gates #355.

### D — Content comes from the map

1. **#326–#329** procgen v4 draw model (content migration, keystone placement, debuff pools, consumer sweep) — **four sub-issues, all drone-ready, self-contained.** The single biggest content-shaping block on the board. (#324 StatPool and #325 draw loop already closed.)
2. #330 wire 4 landmark keystone scenes into procgen — `Needs design`.
3. #336 keystone-as-`.tscn` hub — `Needs design`.
4. #206 spell grants in procgen pools — `Needs design`. Lane C in the old file.
5. #207 spell-grant presence viz (flat placeholder emblem) — `Needs design`.

### E — The player can read it (legibility)

Legibility ships, fidelity defers (rule 4). All tooltip-V2 work below is the "show
everything, no gating" phase — flat placeholders, not carved art.

1. Tooltip V2 cluster, drone-ready: **#343** stat slab spec, **#344** holo panel layout inversion, **#345** glass migration + scanline fix + holo dial-in, **#234** idle-loop animations (REOPENED 2026-08-05 — FanAnimation resource landed; the reopened acceptance — self-contained idle object, null = off, opt-in per unit — is implemented and in review), **#281** addon icon placeholder. (**#236** trace glow moved to lane A.)
2. ~~**#341** RimRing: allocation dial into the shader + archetype legibility — drone-ready.~~ **CLOSED.**
3. ~~**#371** emissive text + composable glow (bloom)~~ — **foundation landed 2026-08-07**, `In review`. Its seven consumer children are **lane A**, not this lane. **#236** (fan trace glow) moved there too — it is glow work, and it should be judged alongside the rest of the glow work rather than next to the tooltip layout units.
4. #354 spell preview UI (per-node damage/hit-count chips) — `Needs design`. The preview-scoped RNG snapshot is the open fork.
5. #361 `core_panel.tscn` carries two skins — `Needs design`, blocks nothing but re-bites fan geometry. A *decision*, not a drone unit.

### F — Balance is tuned, not guessed

The harness shipped ( #268, informative-only). #274's spell damage landed. What remains
is the pinning, not the apparatus.

1. #373 CON→health modeling: `floor(CON / divider_stat)` instead of `core_health_scaling × CON` — `Needs design`, **P0**. The D-21/D-26 precedent being revisited: today `health = 10 + core_health_scaling × CON` via `ExpressionFormula` (continuous, no floor) is the only intrinsic not using `RatioFormula`'s threshold shape. Whether to remap as `floor(CON/threshold_stat)`, which formula class (`RatioStatFormula` sibling vs `ExpressionFormula`), and the retune that preserves published #268 numbers all open. A modeling question upstream of what #278 tunes against — sits alongside #365 as gate-on-the-numbers.
2. #365 mana pool max + regen — `Needs design`, **P0**. Blocks #278: tuning `mana_cost` against placeholder max/regen is tuning against noise.
3. #278 spell balance pass — degree × reach × progression-kind × cost. **A session with the user, not a drone unit.** Runs after #365 and #373.
4. #366 harness: magic-channel fixture + `spell_dpa` readout — `Ready`, follow-up to #268 now that #274 landed.
5. #367 harness: wire the seven comment-registered invariants into `invariants.json` — `Ready`. They're prose on an issue today, not numbers.
6. #248 balancing hub (tracking, `Needs design`).

### G — Onboarding (the game teaches itself)

Not scheduled yet — nothing here is drone-ready. Filed so the lane exists:
#300 removable node blockers (teach combat before the first Entity), #49 tutorial.
Both `Needs design`, P0 when scheduled.

### H — The game plays itself (AI)

**Moved from lane A to last, 2026-08-07** — a scheduling call, not a demotion of the
work. #378 is still the single biggest gap on the board and the sandbox stays a
dollhouse until the AI spends its economy and evaluates its options; the glowup just
went ahead of it. Rule 2 applies: this lane does not open until lane A's scheduled
work ships.

1. **#384** Ownership buckets + `Entity.attitude_to` + `Faction` — **Ready**, and #378's hard prerequisite: today "hostile" means "not me", so AI entities are enemies to each other. Two teams (player / native graph entities), enemies don't fight each other. Absorbed #386 (closed): territory stays strictly per-entity, friendly fire stays per-spell authoring, XP is killer-attributed and hostility-gated.
2. **#385** Set-shaped targeting — **Ready.** The candidate-enumeration API #378's per-candidate EV needs **for ranged and magic**; melee generates candidates by pivot/blade-shape search over the owned subgraph and does not route through `Targeting`. File-disjoint from #384; lands cleaner after it.
3. **#378** AI controller v1: fog-aware tactical loop + MCMC melee + tiered scoring — drone-ready. Supersedes the closed #286 + #174 (their scope folded in, upgraded from shallow/fixed-priority to recon-tactical + per-candidate EV). **Melee budget measured 2026-08-07** (see the issue comment + `test/perf/bench_blade_sim.gd`): a k=20 blade swing is ~13 ms, not µs — ~75 full-fidelity candidates per second, so the plan needs the analytic reach bound + a coarse ranking tier, and `BladeHitScan` is *not* known WorkerThreadPool-safe. Open call from #386 **settled 2026-08-07: per-entity vision, no faction sharing in v1** (#394 files the deferred lever). #378 now has no unanswered design questions.
   - ~~**#279** Enemy CoreClass authoring architecture — drone-ready.~~ **CLOSED.**
4. #47 strategy-pattern NPC controller — `Needs design`, lane H's v2. Not this lane's exit.

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
- #377 stateless-formula refactor: drop `StatModifier._board`/`_bound_sources`, move binding to the Stat/Board owning the modifier — `Needs design`. Long-term answer to the binding-state hazard that #376 (lane B) works around with a single-owner precondition + assertion. Not on the critical path until a feature needs shared instances across multiple owning entities.

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
  20/20 closed. #238 is 1/1 — #341 closed. Both hubs fully shipped.
- **#176 is OPEN but the board says `Done`.** Hygiene flagged it. Close it or move it back.
- **The AI lane's `In progress` count was wrong in the 2026-08-03 FOCUS** — it listed 5 incl. #248,
  but #248 sits in `Needs design`, not `In progress`. Corrected here.

Fixed or obsoleted by this rewrite: #268 and #274 were listed as takeable; both closed
2026-08-03 (17:19 and 16:23 respectively). #357–#359 and #362 had no milestone — assigned
in the prior pass. `hygiene` reports the #176 violation above.

## When this file is wrong

It will go stale, like ROADMAP.md did and like the 2026-08-03 morning version did by
the afternoon. That's fine — it's short enough to rewrite in ten minutes. **Rewrite it
rather than patching around it.** The morning version patched #268/#274 in by hand and
was stale within hours; a rewrite would have caught that they'd just closed.