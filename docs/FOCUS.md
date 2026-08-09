# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the filter on the queue**: if something isn't named below, it isn't
scheduled, regardless of its `Ready` column or priority field.

Rewritten 2026-08-09 (morning cleanup pass). Verified against `gh issue view` /
`gh-project` board state and the actual codebase (git log, `mise run test:one`,
`mise run check`), not just prior FOCUS text — the prior version had drifted hard:
it called seven glow issues "Ready, untouched" when six were already implemented
and sitting in `In review`; it called #378 drone-ready when the board had already
moved it back to `Needs design`; #377 (a whole stateless-refactor issue) shipped
and closed without ever getting a FOCUS update; #327/#328 were called drone-ready
while sitting in `Needs design`.

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

## The headline: lane A's exit condition is met — lane H opens

Lane A's stated exit was **#389 + #388 + #392 shipped**. All three are code-complete
on `master` (verified via `git log`, not just issue status): #388 is closed; #389
and #392 have clean commits with no negative follow-up and sit in `In review`
awaiting issue close. **Rule 2 says lane H (#378, the AI) is now unblocked.**

But #378 itself is **not** drone-ready right now — the board moved it back to
`Needs design` after its own melee-search-budget comment (2026-08-07) surfaced
real open engineering questions: `BladeHitScan.scan` is not verified
WorkerThreadPool-safe (it now queries `PhysicsDirectSpaceState2D`, not pure math),
and the two-tier coarse/full evaluation split needs a decision on whether coarse
ranking preserves top-K ordering. **Next action for lane H is a `/swarmify #378`
session, not a drone dispatch.**

## Right now — drone-ready and scheduled

| # | What | Status |
|---|---|---|
| **#390** | HUD text onto emissive tiers + panel borders | **Partially landed, stays open.** Attribute values, override highlight, Combat Readout border, SP-glow, Hero Sigil ring all shipped. Left undone: Cinzel-font headers can't carry both `CinzelHeader` and a `Tier*` variation at once (`theme_type_variation` is single-slot) — needs a combined variation or a `theme.tres` re-point, and `theme.tres` sits outside this unit's owned paths. A drone can pick this up to finish it. |
| **#362** | `test_fan_scene` trace test is run-order dependent | **Still open, still broken in isolation.** Re-verified this morning: `mise run test:one -- res://test/unit/ui/test_fan_scene.gd` fails `test_no_two_panels_overlap` (panel 0 overlaps panel 4) even after the `a5fd621 fix(#362)` commit landed. That commit fixed a different failure in the same file; this one survived it. Stays `Ready`. |
| **#337 → #332** | Node-local formula modifiers, magnitude scaling | **Children done, hub needs a look.** #374/#375/#376 (all three) are code-complete on master as of this morning (#375 was reopened 2026-08-06 for "programmatically minting stats instead of authoring a `.tres`" — fixed today via #332's own commits: `NodeStatBoard` + `default_node_board.tres` now bake `addon_slots` as an authored intrinsic). Worth a look at whether #332 itself can close. |
| **#347** | SkillNode lab | **Ready**, untouched. |
| **#331** | Harden swarm + drone skills to be harness-independent | **Ready**, untouched. Meta, but real. |
| **#357/#358/#359** | Test coverage: non-melee attack path / propagation filters / graph layer | **Ready**, untouched, all sized. Pull in when a lane needs the coverage. |
| **#369** | bug: loot pickup doesn't clear the carve texture | **Ready**, untouched, no milestone (hygiene flag — assign one before scheduling). |
| **#381** | refactor(outcome): collapse damage/heal slots into `Array[HitInstance]` | **Ready**, untouched, no milestone (same hygiene flag). |
| **#240** | LifeLine grace mechanic | **Ready**, untouched, P2. |
| **#284** | test: targeting + range-finder coverage | **Ready**, untouched. |

## Lane A — the glowup: shipped, awaiting issue close

Every scheduled unit is code-complete on `master`. This is administrative
cleanup, not a lane to schedule drones into.

| # | What | Verified state |
|---|---|---|
| ~~#389~~ | RimRing lit-slot arcs | On master (`5b4d622`). No follow-up complaints. **Close.** |
| ~~#388~~ | Edge lit state emissive | **Already closed.** |
| ~~#392~~ | Attack + allocation VFX emissive | On master (`34610ca`). No follow-up complaints. **Close.** |
| **#390** | HUD text onto tiers | Partially landed — see table above. Stays open. |
| ~~#236~~ | Fan trace glow shader polish | On master (`b8d74f2`). Kept its own scope from #371 as planned. **Close.** |
| ~~#393~~ | Strikethrough toast trace glow | On master (`04f7dd1`). **Close.** |
| ~~#391~~ | `fused_panel` `glow_energy` + instance uniforms | On master, two commits (`a406e08` + follow-up fix `a0f303d`). Touched three out-of-scope panel scenes (`core_panel`/`id_chip_panel`/`addons_panel`) to fix a regression the shared-material change caused — noted on the issue, not hidden. **Close.** |

**#371** (the foundation hub) stays `In progress` until #390 wraps — its other
seven children are closed or closeable. Two follow-on issues, gated behind #261,
not scheduled: **#140** aura fields span edges, **#257** node-shatter texture
fragmentation.

## Lanes, in order — ship the playable loop

### B — The missing combat verb

1. ~~**#337** Staking~~ — **CLOSED.** Shipped.
2. **#332** node-local formula modifiers — children #374/#375/#376 all done (see
   table above); hub itself may be closeable, wasn't independently re-verified
   against its own acceptance list (binding path / cycle gate / recompute-on-change).
3. **#377** stateless `StatModifier` refactor — **CLOSED 2026-08-08.** Shipped
   exactly as scoped: `StatModifier._board`/`_bound_sources` dropped, binding
   moved to `StatBoard`, `_addon_local_clones`/`_addon_entity_clones` deleted via
   `resource_local_to_scene` on the three addon `.tscn`s that carry a
   `StatModifier`. **Did not** delete `_scaled_sets`/`_scaled_effect_sets` — that's
   a real, separate redesign of #376's composition-swap mechanism, correctly
   filed to Backlog as **#398** rather than scope-creeping #377.
4. #338 CommandTray "Manage" mode player-facing surface — `Backlog` (was `Needs
   design`; downgraded — no live parent scheduling it right now).
5. #301 bladesmithing — `Needs design`.

### C — Node-local and aura mechanics actually compute

1. ~~#340 bind() + cycle gate~~ — **CLOSED.**
2. ~~#333 StatFormula `__current` accessor~~ — **CLOSED.**
3. #316 heal aura falls off per hop — `Needs design`.
4. #356 unify `PropagationContext` — `Needs design`. Gates #355.

### D — Content comes from the map

1. **#326, #329** procgen v4 draw model — **CLOSED.** Content migration + consumer
   sweep both shipped.
2. **#327, #328** keystones / debuff pools — **`Needs design`, not drone-ready.**
   Prior FOCUS called all four #326-329 "drone-ready, self-contained" — half of
   that was already wrong.
3. #330 wire 4 landmark keystones into procgen — `Needs design`.
4. #336 keystone-as-`.tscn` hub — `Needs design`.
5. #206 spell grants in procgen pools, #207 spell-grant presence viz — `Needs design`.

### E — The player can read it (legibility)

1. Tooltip V2 cluster: **#343** stat slab spec, **#344** holo panel layout,
   **#345** glass migration, **#281** addon icon placeholder — check current
   status before scheduling, not re-verified this pass. ~~**#234** idle-loop
   animations~~ — **CLOSED.** ~~**#236** trace glow~~ — closed, see lane A.
2. ~~#341 RimRing archetype legibility~~ — **CLOSED.**
3. **#371** — foundation landed, hub stays open pending #390. See lane A.
4. #354 spell preview UI — `Needs design`.
5. #361 `core_panel.tscn` two skins — `Needs design`, a decision not a drone unit.
6. **#380** Tooltip fan: inherited panel scenes, drop manual `FanUnit`
   recomposition — **`Needs design`, but actively being worked**: the five most
   recent commits on `master` (`8c1b683` through `cd3db79`) are all tagged
   `tooltip-fan`/`#380`. This is a live violation (see below) — either it should
   be in `Ready`/named here, or the work in flight should pause for a design
   session. Flagging, not resolving.
7. Node state visuals need a clarity pass (unchanged from prior FOCUS — carried
   forward verbatim, not re-litigated this pass):
   - unallocated nodes need a brighter rim (WIS gold-rim scanning is hard today —
     everything reads dark gray-ish)
   - allocated nodes get lane A's glow, which should help by contrast
   - highlight-ring language is overloaded: hover = yellow outline, Manage-mode
     allocatable = golden-orange ring, attack-plan targeting = yellow/red ring —
     all three compete with the WIS gold-rim signal and need a real visual-design
     pass, not just more colors.

### F — Balance is tuned, not guessed — BLOCKED UNTIL ALL OTHER LANES ARE DONE

1. #373 CON→health remodel — `Needs design`, P0.
2. #365 mana pool max + regen — `Needs design`, P0. Blocks #278.
3. #278 spell balance pass — a session with the user, not a drone unit.
4. #366 harness: magic-channel fixture — `Ready`.
5. #367 harness: invariants.json — `Ready`.
6. #248 balancing hub — `Needs design`, tracking only.

### G — Onboarding

Not scheduled. #300 removable node blockers, #49 tutorial. Both `Needs design`.

### H — The game plays itself (AI)

**Lane A's exit condition is met, so this lane is open per rule 2** — but #378
itself sits in `Needs design`, not `Ready` (see headline above). Its hard
prerequisites are done:

1. ~~#384 Ownership buckets + Faction~~ — **CLOSED.**
2. ~~#385 Set-shaped targeting~~ — **CLOSED.**
3. **#378** AI controller v1 — **`Needs design`.** Melee-budget numbers are in
   (k=20 blade ≈ 13ms solve-only, ~75 candidates/sec single-threaded full-fidelity;
   two-tier coarse/full eval is the biggest lever at ~14x). Per-entity vision, no
   faction-shared reveal in v1, settled 2026-08-07 (deferred lever filed as #394).
   Open before this can dispatch: thread-safety of `BladeHitScan.scan` (now takes
   `PhysicsDirectSpaceState2D`, not verified WorkerThreadPool-safe) and whether
   coarse-tier ranking preserves top-K ordering against the full sim. **Next step:
   `/swarmify #378`, not a drone.**
4. #47 strategy-pattern NPC controller — `Needs design`, v2, not this lane's exit.

## Enablers (pull in only when a lane needs them)

- #249 sandbox host live-tab scaffolding — **7/12 closed** (was reported 6/12;
  #250/#252/#253/#255/#260/#264/#265 closed). Board status is `Needs design`, not
  `In progress` as previously stated — worth reconciling which is true before
  scheduling more of it.
- #349 procgen authoring DX — board now shows `Backlog`, not `Ready` as previously
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

## Known board violations (2026-08-09, verified via `mise run --quiet gh-project -- hygiene`)

- **#176 is OPEN but the board says `Done`.** Confirmed the feature actually
  shipped (Manage-mode allocatable highlighting exists — lane E item 7 above
  describes tuning it further, which presupposes it's there). This is the same
  violation FOCUS flagged on 2026-08-03; it's been sitting for six days. Close it.
- **#238 is `In progress` with its only child (#341) closed.** Nothing left to
  grind — close the hub or file what's actually still open under it.
- **#369 and #381** are `Ready` with no milestone — invisible to `roadmap`.
- **#380 is landing commits while sitting in `Needs design`** — see lane E item 6.
  Not a hygiene-tool violation (the tool doesn't check this), but the same shape:
  board state and reality disagree.

Resolved since the last pass: #159 (was flagged Done-but-open, now genuinely
closed), the AI `In progress` miscount.

## When this file is wrong

It will go stale. That's fine — it's short enough to rewrite in ten minutes.
**Rewrite it rather than patching around it.**
