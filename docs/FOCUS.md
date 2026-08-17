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

Patched 2026-08-15: **lane H (#378, AI controller v1) shipped and closed** the
same day as the last rewrite, after this file was last saved — three slices
landed on master (1fdb2b6, 3339ddf, 7dfe74c) with 5 test files, wired via
`GameRoot._ensure_controllers()`. FOCUS still called it "Ready, dispatch to a
drone" for six days. Caught by an `Explore` check against `gh issue view` + git
log, not a full re-audit — treat the rest of this file's dates as unverified
since 2026-08-09.

Patched 2026-08-17: **two new lanes added at the top — M (meta-shell & modes) and
P (performance)** — plus a North Star section. Lane M's Tier-S plumbing is
already shipped in a worktree (verified, see the lane). Lane P is new and is now
the highest-priority *unscheduled* work: a real, reproducible framerate collapse
found in playtesting. **Nothing below lane P was re-verified this pass** — lanes
A–H carry their 2026-08-09/15 state and their dates remain unverified.

## North Star

The bar this project is aiming at, so a perf or scope call has something to be
judged against:

1. **A 2000-`SkillNode` map runs smoothly at 144Hz, at 1440p.** Note the dev
   sandbox is *not* 1440p today, so current local framerates are optimistic
   about resolution and pessimistic about nothing. This is the number that
   decides whether a rendering or recompute approach is acceptable — see
   `.claude/rules/skill-node-scale.md`.
2. **The player can control that**: windowed / fullscreen / borderless,
   resolution, vsync, framerate cap — the standard shenanigans. The settings
   substrate for this shipped today (lane M); the display settings themselves
   have not been authored.
3. **LAN-playable**: single-player, seeded runs, and hot-seat coop by
   **2026-08-31**, with versus if it fits. See lane M.

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

## Lane order, and what rule 2 means now (2026-08-17)

Two lanes were inserted above B: **P (performance)** then **M (meta-shell)**.
Rule 2 says one lane at a time, so state the exceptions rather than quietly
violating it:

- **Lane P outranks everything**, including M. A 6fps late game makes the LAN
  build unshippable regardless of how good its menus are. But P opens with a
  *diagnosis* unit, which is measurement, not implementation — M's remaining
  units may proceed in parallel while that profile is being taken.
- **Lane A's two open units (#389, #392) are owner-eyeball tuning**, not drone
  work. They coexist with P and M by nature: they are not dispatchable, they are
  you looking at glow values. Not a rule-2 violation.
- **Lane B's tail (#406 `In review`, #338 `Ready`) is PARKED** until lane P has
  a diagnosis. It's close to done and it is genuinely tempting, but it is not on
  the LAN critical path and it is not the framerate.

## The headline: lane A is most of the way shipped, lane H is CLOSED

Lane A's stated exit was **#389 + #388 + #392 shipped**. #388 is closed. #389 and
#392 are code-complete but **not tuned yet** — owner call, not a code question:
glow/emission values and arc positioning on #389 still need eyeballing, and #392
lost focus to #388/mod-slab work and hasn't been tuned. Both stay open.

**#378 (the AI, lane H) is CLOSED — shipped 2026-08-09, after this file's last
rewrite.** Landed in three sequenced slices, all on master: `ai_recon.gd`
(1fdb2b6, fog-aware recon short-circuit), `ai_combat_scorer.gd` (3339ddf, shared
per-candidate EV scorer), `ai_blade_rollout.gd` (7dfe74c, melee MCMC rollout —
commit message "closes AI v1"). `AIController` is wired in via
`GameRoot._ensure_controllers()`, attached to entities automatically; 5 test
files cover it (`test_ai_controller*`, `test_ai_recon`, `test_ai_combat_scorer`,
`test_ai_blade_rollout`). The `BladeHitScan.scan` threading question (thread
`BladeSim.simulate` only, keep `scan` main-thread against a pruned finalist set)
shipped as scoped. Archetype/personality (Caster/Bruiser/Ranger) stays out of
scope, filed as **#410** (`AiWeights` follow-up, `Backlog`, blocked-by #378 —
now unblocked since #378 closed). **Lane H's exit condition is met; nothing left
to dispatch there.**

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

### New this pass (2026-08-17) — from playtesting, all still to be FILED

Small, diagnosed down to the line, and file-disjoint from lanes M and P. Cheap
Sonnet-tier units once they have issue numbers.

| What | Diagnosis |
|---|---|
| **CommandTray: two buttons lit at once** | Root cause found. `AttackModeButton.override_toggle()` uses `set_pressed_no_signal` (`attack_mode_button.gd:89`), which bypasses the `ButtonGroup`'s unpress-others pass — a raw click presses X via the group while `set_active_mode(Y)` presses Y without clearing X. Compounded: `AttackModeBar._active_mode` only updates from `BattleSystem.attack_plan_changed`, so a rejected request (no AP) never resyncs. Fix: bar becomes a pure view, re-asserting full group state after *every* press; `BattleSystem` always emits an outcome. |
| CommandTray: icons for the 4 mode buttons | Prefix or inset, whichever reads better. |
| Melee body: `clamp` / `spike` addon buttons | Need icons, colors, and legible active/inactive states — currently bare text. |
| **Melee: "reform last blade"** | Store the last `AttackPlan` excerpt + a topology hash of the owned subgraph; enable only if the hash still matches (allocation-superset is fine, e.g. after a stake) and the plan fits current AP. |
| `StatModifier.resource_name` | Inspector shows a useless "StatModifier". `stat_modifier.gd` already has `format()` (`:231`) and `contribution_text()` (`:190`) that build the right string, and `StatPool` already does this (`stat_pool.gd:97`) — wire `resource_name` off `stat_id`/`operation`/`value` change. |
| Procgen: `@export_group` the config exports | Pure ergonomics. |
| **Clamp edge width vs. zoom** | Widened edges out-scale the nodes when zoomed out: edge width is screen-constant via the `edge_camera_zoom` global uniform, while nodes scale with the camera. Needs a zoom-dependent clamp width factor **plus** the "bolt" dots at each connection point (edge-colored, equal or stronger bloom). `edge.gd:228-238`, `edge_mesh.gdshader:80-81`. Wants a real design pass, not just a constant. |

### `Needs design` — new this pass, genuine open forks

**Tier-ladder / roll redesign** (this is roughly the 8th pass at the roll model —
it needs a `/swarmify` session with the owner, not a drone). Three tangled forks:
(a) **decouple cost tier from value tier** — a rare `-1 min_damage_taken` should
be able to cost 4–8 without its base value being multiplied by the t3 ladder;
`min_tier` currently conflates the two (`stat_pool.gd:107-123`), and nobody sane
authors "value = X/7" to compensate; (b) **roll uniformly between the previous
tier's value and this one's** (t3 → 4.0–7.0) instead of always the exact ladder
value, which is why the game is full of tell-tale "+7%" and "×1.75" repeats;
(c) replace the single `tier_bias_k` exponent (`stat_pool.gd:129`) with
composable weight-curve micro-resources plus an `Expression` escape hatch, so a
pool can make high tiers **rarer** than low ones — impossible today.

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

### P — The framerate collapse — TOP PRIORITY, DIAGNOSIS FIRST

**Found in playtesting 2026-08-17 and it is severe.** At level ~100 (≈200 owned
SkillNodes): idle is fine at 144fps, but **allocating a node drops to ~15fps at
100 owned and ~6fps at 200 owned**. If the rolled modifier includes `PER` or
`vision_range`, it drops harder still. This blocks North Star #1 outright, and
it degrades with *player progress*, which means it gets worse exactly as a run
gets interesting.

**The diagnostic anomaly, and why it's the most useful clue.** The drop is not a
single stalled frame — it **persists for 5–10 seconds** and then recovers to
144fps on its own. The owner's question is fair: with no threading, and given
`call_deferred` flushes at end-of-frame rather than spreading across frames,
what sustains a hitch across hundreds of frames? Real mechanisms that produce
exactly this shape:

- **A per-frame callback driving a recompute.** A tween / `AnimationPlayer` /
  VFX whose frame callback triggers stat or vision recomputation costs its full
  price every frame for the animation's duration. Multi-second recovery matches
  an *animation length* far better than it matches any one-shot cost — this is
  the leading hypothesis.
- **A frame-yielding coroutine.** Anything doing `await get_tree().process_frame`
  inside a loop spreads real work across frames by construction.
- **Cascading re-entrant recompute.** Derived stats recomputing derived stats,
  each re-triggering the next, with the work re-queued rather than coalesced.

Recovery-to-144fps rules *out* a permanent complexity increase (a steady-state
O(owned²) walk would never recover), and rules *in* something transient but
frame-repeated.

**MEASURED 2026-08-17 — the re-entrancy suspect below is DEAD, and a real
19.4ms recompute was found and fixed in its place.** Instrumented at the North
Star scale (2025 nodes, 200 owned) in `test_vision_recompute_scaling.gd`:

- One allocation produces **exactly one** `_recompute()`. `_recompute_pending`
  is never re-armed during the pass. The cross-frame chain described below does
  not exist. (It was a good hypothesis and the right shape; it just isn't what
  the code does.)
- But **one `_recompute()` cost 19.4ms** — 2.8x the entire 6.9ms frame budget at
  144Hz — and 13.3ms of that was the visibility pass, a per-node linear scan
  over every owned circle (2025 x 200 = 400k GDScript iterations). `AiRecon`
  ran the same quadratic shape per AI turn.
- **Fixed** by `VisionCircles` (a uniform grid, exact not approximate; shared by
  both consumers so the vision rule stays single-sourced). **19.4ms -> 6.5ms**,
  and cost stopped tracking owned count: 25x the owned nodes now costs 1.75x the
  recompute, was ~5x. Regression tests pin both properties.

**Still open, and this is now the lane's real question:** the *sustained* 5-10s
drop is unexplained. The fixture has no FogOverlay, no HUD, no VFX, and its
idle frames cost exactly as much as its post-allocation frames — so the
per-frame repeater lives outside `vision_system.gd`. Next suspects, in order:
**`FogOverlay._refresh`**, which runs on every `vision_render_tick` for the
~0.9s circle animation and rebuilds a 200-entry source array each time — and
note **#133 was already exactly this**: `_apply_per_element_dimming` was
O(elements × sources) *per frame* off that same signal, costing 17–150ms/frame,
with the shader blamed and innocent. A sustained multi-second drop that recovers
on its own is the signature of that shape, not of a one-shot cost;
allocation VFX; StatBoard recompute repeats (suspect 2 below, still unmeasured).
Next unit is a profile of the *real* scene, not another synthetic fixture.

<details><summary>Original hypothesis, kept for the record — disproven</summary>

**Prime suspect — a specific, testable re-entrancy hole (found 2026-08-17):**

The owner's hypothesis was that `+1 PER` makes all ~200 owned nodes recompute
their local `vision_range` and animate, one recalc per frame until they settle.
The fan-out half is real — `_rebind_local_stats` binds *every* owned node's
`vision_range`/`sensor_range` to `_request_recompute` — but it is **already
absorbed**: `_request_recompute` debounces via `_recompute_pending`, and its
docstring documents this exact bug as previously fixed. The `_process` animation
loop is also clean; it only lerps `_circles` and never calls `_recompute`.

The hole is one line away, in `_recompute_deferred`:

```gdscript
func _recompute_deferred() -> void:
	_recompute_pending = false   # cleared BEFORE the work
	_recompute()                 # any value_changed in here re-arms the flag
```

`_recompute()` calls `_rebind_local_stats(all_owned)` *inside itself*
(`vision_system.gd:331`), disconnecting and reconnecting 2 stats per owned node
— 800 signal ops at 200 owned. If anything in that pass emits `value_changed`,
the flag re-arms and a **full recompute is deferred to the next frame**, which
re-arms it again. That is a self-sustaining chain of one O(graph × owned)
recompute per frame that terminates only on quiescence — and it matches all four
symptoms: multi-second duration with no threading, full recovery, the
`PER`/`vision_range` specificity, and superlinear scaling with owned count.

Note this is **not** what the existing re-entrancy guard covers: that prevents
recursion *within* a frame; this leaks *across* frames, which is exactly why it
presents as though something were threaded.

**The decisive experiment (do this first, it is cheap):** count `_recompute()`
calls per allocation at ~200 owned. One → hypothesis dead, move to suspect 3.
Hundreds spread across frames → confirmed; fix by clearing `_recompute_pending`
*after* `_recompute()` returns, plus a guard so requests raised during a
recompute coalesce into exactly one follow-up rather than one per emitter.

</details>

2. **StatBoard recompute coalescing.** A level-100 board carries a lot of
   modifiers. There is no dirty-marking / batched-flush model (the Vue-style
   "mark dirty, recompute once at flush" the owner described); there is only a
   re-entrancy guard, which prevents *loops* but not **redundant repeats**. Those
   are different problems and the guard does not solve the second.
3. **Fog overlay uniform upload.** The vision-circle array pushed to shader
   globals grows with owned nodes; re-uploading it per change is a per-frame CPU
   cost that would track owned-node count.

**Rule 1 of this lane: profile before touching anything.** Twice already in this
project the culprit was a quadratic CPU walk and not the GPU — measure with the
Godot profiler at 200 owned nodes and identify the actual hot callback *before*
proposing a fix. A fix chosen from this list without a measurement is a guess.

**Exit condition:** 2000-node map, 200 owned, allocation at a steady 144fps at
1440p. **File as an epic with a diagnosis child first**, then fix children.
Nothing else in this lane opens until the profile exists.

**Progress 2026-08-17:** the vision half is done and landed on master — see the
measured block above. The exit condition is **not** met: it needs the owner's
eyeball at 1440p in the real game, and the sustained-drop mechanism is still
unidentified.

### M — Meta-shell & modes — LAN by 2026-08-31

Full design: `/home/bramh/.claude/plans/done-a-lot-of-whimsical-noodle.md`.
Menus → lobby → run, a `Participant` roster, seeded runs, hot-seat coop, a win
condition, and a serializable command bus so versus is a transport swap rather
than a rewrite.

**Tier-S plumbing: SHIPPED 2026-08-17**, in worktree `wt-meta-shell-tier-s`
(4 commits, not yet merged to master). Verified this pass: `mise run check`
clean, all four new test files pass, no forbidden file touched.

| Unit | State |
|---|---|
| `SceneDirector` (absorbs + deletes the zero-caller `SceneLoader`, #212) | **Done** |
| `session/` data classes — `Participant`, `RunConfig`, `ParticipantRoster`, `RunOutcome` | **Done** |
| `GameSettings` + reflected settings menu + `ConfigFile` persistence | **Done** — this is the substrate North Star #2 needs |
| `BuildInfo` + pause-menu seed/branch/worktree footer | **Done** |
| `SkillNode.stable_id` + `Graph.get_by_stable_id` | **Done** |

**Still open, in order:**

1. **`GameSession` + one-shot seed resolution.** Seed 0 *does* randomise
   (`graph_procgen.gd:83`) but the `randi()` is thrown away, so a good run can
   never be replayed or shared; and the sentinel is resolved a *second* time,
   differently, in `procgen_play_sandbox.gd:97` (`hash()` of a literal = a fixed
   constant). Resolve once in `GameSession`, feed both streams. **Owner decision,
   not a drone unit** — it is the determinism contract versus depends on.
2. **`CommandBus`** + reroute `PlayerInputController`. Hard: 850-line file, an
   armed-mode stack, `await` interleaving, and `bool` returns becoming signals.
   Needs the serial queue + `is_applying` guard on day one.
3. **Three rebind seams** (`HudRoot.rebind_player`, input transient-state reset,
   camp-wide `VisionSystem.viewers`) + **`VictorySystem`**. Delivers hot-seat
   coop and the first-ever win condition. **Two traps found by inspection:**
   `game_root.gd:202` force-assigns `_PLAYER_FACTION` so a second human is
   *hostile to its own teammate*, and `:221` hands any non-`player` entity an
   `AIController` so player 2 plays itself.
4. **Meta scenes, unstyled** — main menu, new game, lobby.
5. **Display settings** (windowed/fullscreen/resolution/vsync/fps cap) authored
   onto `GameSettings`. Cheap now that the substrate exists; North Star #2.
6. **Versus** — `NetworkTransport`, ENet lobby. Only if 1–5 are solid. Note
   `entity/factions/` holds only `player.tres` and `npc.tres`, so 4-player
   versus needs camps authored or everyone reads `ALLIED`.

**Merge `wt-meta-shell-tier-s` to master before opening unit 1** — it edits
`project.godot` autoloads and will conflict with anything else that does.

### B — The missing combat verb — nearly closed

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
4. ~~**#411**~~ Design: unify click grammar — **CLOSED.** Right-click pops one
   level off an arm/origin/target stack; self-targeting resolves through
   ordinary target validity, no special case.
5. ~~**#404**~~ Shared targeting-mode system (arm/cancel/select) — **CLOSED**,
   re-spec'd against #411's decision and shipped.
6. ~~**#405**~~ addon-dispatch parity fix (`MeleeAttackPlan.build_blade_state`)
   — **CLOSED.**
7. **#406** the temp Clamp/Spikes budget spend — board status **`In review`**.
   Depended on #404 (dispatch) + #405 (parity fix), both closed; land this to
   close #301's hub.
8. **#338** CommandTray "Manage" mode player-facing surface — board already
   shows **`Ready`** (its #404 blocker is closed). Acceptance spec on the issue
   is fully written — reuses #404's dispatcher for Stake/Extract, existing
   raw-click channels for Allocate/Move Core/Deallocate. Verify it doesn't need
   a fresh design pass before dispatching.
9. **#412** HUD viewport tint for currently-armed mode — `Backlog`, not
   scheduled. Reuses #411's now-shipped armed-mode concept; not
   structurally blocked/blocking, just sequenced after so it reads the
   unified state instead of `BattleSystem.attack_mode` alone.
10. **#301** bladesmithing hub — board status **`In progress`**. Closes once
    #406 merges. **#409** edge sharpeners stays `Needs design`, blocked on
    **#407** (velocity-based blade/edge damage, `Backlog`, no shape yet).
    **#408** (Clamp secondary use) is a parked aside, `Backlog`. Per #301's own
    acceptance-spec comment, #409/#407/#408 do **not** gate the hub closing.

**Lane B's exit is #406 landing + #338 dispatched/shipped** — everything else
in the lane (#412, #409, #407, #408) is explicitly deferred, not on the
critical path.

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

### H — The game plays itself (AI) — CLOSED

**Lane H — done.** #378 shipped and closed 2026-08-09 (see headline). Its
prerequisites and the unit itself:

1. ~~#384 Ownership buckets + Faction~~ — **CLOSED.**
2. ~~#385 Set-shaped targeting~~ — **CLOSED.**
3. ~~#378~~ AI controller v1 — **CLOSED.** Melee-budget numbers held up
   (k=20 blade ≈ 13ms solve-only, ~75 candidates/sec single-threaded
   full-fidelity; two-tier coarse/full eval the biggest lever at ~14x).
   Per-entity vision, no faction-shared reveal in v1 (deferred lever filed as
   #394). `BladeHitScan.scan` threading shipped as spec'd. Archetype
   personality pulled out of scope, filed as **#410** (`Backlog`,
   blocked-by #378 — now unblocked).
4. #410 AiWeights archetype personality — `Backlog`, unblocked now that #378
   is closed, not yet scheduled into a lane.
5. #47 strategy-pattern NPC controller — `Needs design`, v2, not this lane's exit.

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
