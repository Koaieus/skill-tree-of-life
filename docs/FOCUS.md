# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the filter on the queue**: if something isn't named below, it isn't
scheduled, regardless of its `Ready` column or priority field.

Rewritten 2026-08-09, twice today. First pass verified the board against the
codebase (git log, isolated `mise run test:one`, `mise run check`) and found real
drift — six glow issues called "Ready, untouched" were already implemented and
sitting in `In review`; #378 was called drone-ready when the board had already
bounced it to `Needs design`; #377 shipped and closed without ever hitting FOCUS;
#327/#328 were called drone-ready while in `Needs design`. Second pass folded in
the owner's per-issue review of that findings table — several "done" calls needed
owner judgment code inspection can't make (is a glow *tuned*, not just present).

## Why this file exists

The board sprawls. This file is the antidote: it names what's actually next, and
by omission says everything else is not.

There is one queue for "needs design" work — **#261** (the swarmify pipeline). If
an issue is in `Needs design`, it sits there until a `/swarmify` pass settles its
forks and moves it to `Ready`. **FOCUS does not catalog `Needs design` work.**

## The rules (unchanged, still load-bearing)

1. **WIP limit: 5 — and it is the weakest rule here.** The real failure mode is
   things *rotting* `In progress`. Judge the column by age, not by count.
2. **One lane at a time.** Lanes below are ordered. Don't open lane N+1 while lane N
   has unfinished scheduled work.
3. **A fork is a Backlog issue, never an immediate start.** File it, finish the
   current unit, re-read this file.
4. **Legibility ships, fidelity defers.**
5. **Crappy-now beats correct-later for anything not on the critical path.**
6. **`Ready` is a superset, not the queue.** Being `Ready` means "a drone *could*
   take this"; being named below means "a drone *should*".

## The headline: lane A is most of the way shipped, lane H needs a design session

Lane A's stated exit was **#389 + #388 + #392 shipped**. #388 is closed. #389 and
#392 are code-complete but **not tuned yet** — owner call, not a code question:
glow/emission values and arc positioning on #389 still need eyeballing, and #392
lost focus to #388/mod-slab work and hasn't been tuned. Both stay open.

**#378 (the AI, lane H) sits in `Needs design`**, not `Ready` — the board bounced
it there after a melee-search-budget comment surfaced real open questions:
`BladeHitScan.scan` is not verified WorkerThreadPool-safe (it now queries
`PhysicsDirectSpaceState2D`, not pure math), and the two-tier coarse/full eval
split needs a decision on whether coarse ranking preserves top-K ordering.
**Next action for lane H is `/swarmify #378`, not a drone dispatch** — confirmed,
this is the lane-H entry in the ordered list below.

## Right now — drone-ready and scheduled

| # | What | Status |
|---|---|---|
| **#347** | SkillNode lab | **Ready**, untouched. |
| **#331** | Harden swarm + drone skills to be harness-independent | **Ready**, untouched. Meta, but real. |
| **#357/#358/#359** | Test coverage: non-melee attack path / propagation filters / graph layer | **Ready**, untouched, all sized. Pull in when a lane needs the coverage. |
| **#369** | bug: loot pickup doesn't clear the carve texture | **Ready**, untouched, no milestone (hygiene flag — assign one before scheduling). |
| **#381** | refactor(outcome): collapse damage/heal slots into `Array[HitInstance]` | **Ready**, untouched, no milestone (same hygiene flag). |
| **#240** | LifeLine grace mechanic | **Ready**, untouched, P2. |
| **#284** | test: targeting + range-finder coverage | **Ready**, untouched. |

## Lane A — the glowup: mostly shipped, two units still mid-tune

| # | What | State |
|---|---|---|
| **#389** | RimRing lit-slot arcs | Code on master (`5b4d622`), **not tuned** — owner still adjusting glow/emission values and arc positioning. Stays open. |
| ~~#388~~ | Edge lit state emissive | **CLOSED.** |
| **#392** | Attack + allocation VFX emissive | Code on master (`34610ca`), **not tuned** — yesterday's focus went to #388/mod-slabs instead. Stays open. |
| ~~#390~~ | HUD text onto tiers | **CLOSED 2026-08-09.** Header component sweep landed; owner calls it done. Cinzel-font/`Tier*` variation conflict can be tuned later without reopening. |
| ~~#236~~ | Fan trace glow shader polish | **CLOSED.** Mostly done tweaking; glow fadeout added. |
| **#393** | Strikethrough toast trace glow | **Scope grew, stays open.** Owner wants more than a glow — the trace tip should read as a blooming laser cutter cutting across, not a static line. Comment on the issue records this. |
| ~~#391~~ | `fused_panel` `glow_energy` + instance uniforms | **CLOSED.** Knobs are set up for later tuning without reopening. |

**#371** (the foundation hub) stays open pending #389/#392/#393. Two follow-on
issues, gated behind #261, not scheduled: **#140** aura fields span edges,
**#257** node-shatter texture fragmentation.

## Lanes, in order — ship the playable loop

### B — The missing combat verb

1. ~~**#337** Staking~~ — **CLOSED.** Shipped.
2. ~~#332~~ node-local formula modifiers — **CLOSED 2026-08-09.** Re-verified
   against master: binding path, cycle gate, formula reachability
   (`stake_level__current`), and recompute-on-change all shipped and tested
   (37/37 across `test_node_local_bind`/`test_addon_slots`/`test_local_scaling`/
   `test_stake_level_poolstat`). `NodeStatBoard extends StatBoard` (owner's
   follow-up ask) also confirmed landed (`stats_system/node_stat_board.gd`).
3. **#377** stateless `StatModifier` refactor — **CLOSED 2026-08-08.** Shipped
   exactly as scoped. **Did not** delete `_scaled_sets`/`_scaled_effect_sets` —
   that's a real, separate redesign of #376's composition-swap mechanism,
   correctly filed to Backlog as **#398** rather than scope-creeping #377.
4. #338 CommandTray "Manage" mode player-facing surface — `Backlog`.
5. #301 bladesmithing — `Needs design`.

### C — Node-local and aura mechanics actually compute

1. ~~#340 bind() + cycle gate~~ — **CLOSED.**
2. ~~#333 StatFormula `__current` accessor~~ — **CLOSED.**
3. #316 heal aura falls off per hop — `Needs design`.
4. #356 unify `PropagationContext` — `Needs design`. Gates #355.

### D — Content comes from the map

1. **#326, #329** procgen v4 draw model — **CLOSED.** Content migration + consumer
   sweep both shipped.
2. **#327** keystones — `Needs design`, and per the owner **needs a real design
   pass**: settle intent with named examples, multiple back-and-forths, no coding
   yet. Standing observation from this session: more "visionary" design docs in
   general would help steer agent work even when instructions stay loose — worth
   the pattern beyond just #327.
3. ~~**#328**~~ debuff pools — **CLOSED 2026-08-09.** Debuff pools already exist
   and roll on procgen (e.g. `constitution.tres`'s `-%INT` tiers, 3 tiers). This
   ticket's refund-threshold spec (D9) isn't what shipped; further debuff content
   is pure design/authoring from here, not code — no ticket needed for more of it.
4. #330 wire 4 landmark keystones into procgen — `Needs design`.
5. #336 keystone-as-`.tscn` hub — `Needs design`.
6. #206 spell grants in procgen pools, #207 spell-grant presence viz — `Needs design`.

### E — The player can read it (legibility)

1. Tooltip V2 cluster: **#343** stat slab spec, **#344** holo panel layout,
   **#345** glass migration, **#281** addon icon placeholder — not re-verified
   this pass. ~~**#234**~~ idle-loop animations — **CLOSED.** ~~**#236**~~ trace
   glow — closed, see lane A.
2. ~~#341 RimRing archetype legibility~~ — **CLOSED.**
3. **#371** — foundation landed, hub stays open pending lane A's tail. See lane A.
4. #354 spell preview UI — `Needs design`.
5. #361 `core_panel.tscn` two skins — `Needs design`, a decision not a drone unit.
6. **#380** Tooltip fan: inherited panel scenes, drop manual `FanUnit`
   recomposition — moved to **`In review`** (was `Needs design` while commits kept
   landing against it — a real design+impl pass happened; owner still wants to
   take it for a spin to find hurdles before calling it settled).
7. **#362** `test_fan_scene` panel-overlap test — moved to **`Needs design`** (was
   `Ready`). Re-verified broken in isolation (`test_no_two_panels_overlap` still
   fails). Owner reframe: instead of patching the no-overlap check to be
   order-independent, consider panels that push/pull each other and readjust
   dynamically, sidestepping overlap detection rather than fixing it. Comment on
   the issue records this — needs a design pass before more drone time on the
   current approach.
8. Node state visuals need a clarity pass (unchanged from prior FOCUS):
   - unallocated nodes need a brighter rim (WIS gold-rim scanning is hard today —
     everything reads dark gray-ish)
   - allocated nodes get lane A's glow, which should help by contrast
   - highlight-ring language is overloaded: hover = yellow outline, Manage-mode
     allocatable = golden-orange ring, attack-plan targeting = yellow/red ring —
     all three compete with the WIS gold-rim signal and need a real visual-design
     pass, not just more colors. (Not #176 — that issue was the original
     manage-mode highlight feature, long shipped and closed 2026-08-09; this is
     the follow-up unification ask.)

### F — Balance is tuned, not guessed — BLOCKED UNTIL ALL OTHER LANES ARE DONE

1. #373 CON→health remodel — `Needs design`, P0.
2. #365 mana pool max + regen — `Needs design`, P0. Blocks #278.
3. #278 spell balance pass — a session with the user, not a drone unit.
4. #366 harness: magic-channel fixture — `Ready`.
5. #367 harness: invariants.json — `Ready`.
6. #248 balancing hub — `Needs design`, tracking only.

### G — Onboarding

Not scheduled. #300 removable node blockers, #49 tutorial. Both `Needs design`.

**New this pass — #403** (design, Backlog): Tech Seeds — an existing, fully
documented but never-acquired mechanic (`docs/design/skill_node_addons.md`) —
acquired by defeating passive blocker enemies that sit on a node preventing its
allocation (a #300 variant, entity rather than inert HP-gate). Open forks:
mid-level maturation vs. harvest-at-level-completion, and if timing stops gating
fruit quality, what replaces it (baked tier-cost curve vs. per-turn progress
roll — see procgen's existing budget/tier draw loop, #326-329, as the likely
reusable shape). Needs a real back-and-forth design session, not a solo read.

### H — The game plays itself (AI)

**Lane H — confirmed.** #378 sits in `Needs design`, not `Ready`. Its hard
prerequisites are done:

1. ~~#384 Ownership buckets + Faction~~ — **CLOSED.**
2. ~~#385 Set-shaped targeting~~ — **CLOSED.**
3. **#378** AI controller v1 — **`Needs design`.** Melee-budget numbers are in
   (k=20 blade ≈ 13ms solve-only, ~75 candidates/sec single-threaded full-fidelity;
   two-tier coarse/full eval is the biggest lever at ~14x). Per-entity vision, no
   faction-shared reveal in v1, settled 2026-08-07 (deferred lever filed as #394).
   Open before this can dispatch: thread-safety of `BladeHitScan.scan` and
   whether coarse-tier ranking preserves top-K ordering against the full sim.
   **Next step: `/swarmify #378`.**
4. #47 strategy-pattern NPC controller — `Needs design`, v2, not this lane's exit.

## Enablers (pull in only when a lane needs them)

- #249 sandbox host live-tab scaffolding — **7/12 closed** (was reported 6/12).
  Board status is `Needs design`, not `In progress` as previously stated — worth
  reconciling which is true before scheduling more of it.
- #349 procgen authoring DX — board shows `Backlog`, not `Ready` as previously
  stated.

## Deliberately parked

Unchanged from the prior pass — not re-audited this cycle:

| Parked | Why |
|---|---|
| #165 pre-authored clusters in procgen | planarity + stitching research. |
| #245, #167, #342, #142 emblem/carve substrate + rune art | fidelity, not legibility. |
| #348 addon placement UX | wholly undesigned. |
| #355 Chromatic Cascade | gated on #356 and on having played Resonator. |
| #313 ArchetypePolicy clustering dials | overlaps stamping/cluster work. |
| #23 pre-authored sandbox content / save-load | metagame; loop isn't playable yet. |
| #256, #257 blade node visual upgrade, InnerDisk shatter | VFX juice. |
| #304 retire `BaseCircle` | refactor cleanup, no gameplay consequence. |
| #197 double-crit as a tier | enhancement on working crits. |
| procgen "stamping" | detour; don't reopen. |

## Known board violations (2026-08-09)

- ~~#176 OPEN but board says Done~~ — **CLOSED 2026-08-09.** Six days sitting as
  a known violation before it got cleared.
- **#238 is `In progress` with its only sub-issue (#341) closed — investigated,
  not a false positive.** #341 closing does NOT mean #238 is done: #238's own
  body is a **verdict task** on the *other* five visual encoders (RimRing,
  RimBonuses, RuneRing, CoreHalos/CoreSigilBloom, SensedOutline, BaseCircle) —
  each needs an explicit KEEP/MERGE/CUT applied, gated on #132 (rune ring vs. rim
  diamonds) resolving first. Nothing in the codebase shows that verdict has been
  made. Stays `In progress`, genuinely — this was a correct hygiene flag on the
  child-count check but the hub itself is real unfinished design work, not
  administrative residue.
- **#369 and #381** are `Ready` with no milestone — invisible to `roadmap`.
- ~~#380 landing commits while `Needs design`~~ — resolved by moving it to
  `In review` (see lane E item 6), matching where the work actually is.

## When this file is wrong

It will go stale. That's fine — it's short enough to rewrite in ten minutes.
**Rewrite it rather than patching around it.**
