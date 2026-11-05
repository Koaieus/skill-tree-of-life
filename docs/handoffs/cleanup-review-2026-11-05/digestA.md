# Digest A (specs dated 2026-11-05; checked vs origin/master)

### #1014 Stale "In progress" claim detector (hygiene)
- **What:** add report-only `hygiene` check `in_progress_stale` (leaf issues In progress with no activity for >6h); optional `--fix` flips them back to Ready.
- **Why now / value:** unattended drones that die leave issues stuck In progress, invisible to the queue; this surfaces them.
- **Size:** s-m, 4 files (gh-project, hub_derive.jq or new claims.jq, gh-project-selftest, issue-workflow.md).
- **Calls baked in:** (1) 6h threshold, env `GH_PROJECT_IN_PROGRESS_STALE_HOURS`. (2) Hubs never reported. (3) Activity = max(issue updatedAt, any-branch commit citing #n, worktree HEAD mtime). (4) `--fix` moves to Ready ONLY if the status timeline shows previous lane was Ready; else report-only. Drone must probe whether the token can read `ProjectV2ItemStatusChangedEvent`, else ships with no --fix. This is the one real behaviour call: an auto-mutating board fix. (5) Declines to add `hub_in_progress_no_active_child` (claims `stalled_hub` covers it; true in hub_derive.jq, though that one only fires for all-parked children, not "hub In progress with no active child" in general).
- **Drone-readiness:** premises hold (STALE_CLAIM_HOURS, `stale_claim` section, `_section` list, selftest all exist; no in_progress_stale yet). Soft spots: worktree-to-issue mapping is "if a stable mapping exists, else skip" (drone judgment); `updatedAt` is already fetched so signal (a) is free. A 6h cutoff will flag any long-running legit drone with no commit/comment, but it is report-only so low harm. Acceptance is concrete jq fixtures.
- **Rec:** READY-after-tweak: decide whether you want the `--fix` arm at all; simplest is to strike it (report-only, matches `stale_claim`) so nothing auto-mutates the board.

### #427 Make `SkillNode.self_loops` runtime-only (stop serializing it)
- **What:** drop `@export` on `self_loops`, delete the two baked `.tscn` entries, make `self_loop_count` ignore freed/null, have Edge unregister on endpoint change / `_exit_tree`.
- **Why now / value:** derived state is serialized by the editor and once baked a null that inflated degree (+2) and spell min_degree gating. Structural fix.
- **Size:** m, 7 files (skill_node.gd, edge.gd, graph.gd maybe, 2 .tscn, 2 tests).
- **Calls baked in:** keep the index (not derived from edge list, rejected as hot-path O(edges)); counts valid entries only; Edge becomes sole (un)registrar. No owner pass, all labelled tentative but conventional.
- **Drone-readiness:** premises verified: `@export var self_loops` at skill_node.gd:233, edge.gd:401/454, graph.gd:564, both .tscn bakes (dev_sandbox:731/738, playground_panel:262/265) still present. Risks: hand-editing `.tscn` `node_paths=` is fiddly, and `mise run refresh` may re-save them; also `@tool` Edge in the editor means runtime-only var must be rebuilt on scene load (setters already do, per spec). Spec admits the "corrupt bake" symptom is already fixed, so this is hardening, not a live bug. Test 1 text-scans .tscn files (a bit brittle but fine).
- **Rec:** READY. Low-moderate value; mechanical.

### #436 Replace dict-row grant ledger with Grant / ModifierGrant / TagGrant classes
- **What:** `EffectInstance._grants` goes from `Array[Dictionary]` with a `&"kind"` switch to typed `Grant` subclasses with `apply/revert`; `revoke`/`revoke_all` become polymorphic.
- **Why now / value:** removes a duplicated kind-switch (effect_context.gd:172-188 verified) so a third grant kind is one subclass. Pure refactor.
- **Size:** m, ~6 files (3 new grant classes + .uid, effect_instance, effect_context, test_effect, effect-system.md).
- **Calls baked in:** RefCounted not Resource; handle contract unchanged (clone_for shares LIVE handle, `duplicate_row()` makes a new Grant); `_detach`/`_apply_tag` become public `detach_modifier`/`apply_tag` on EffectContext; `forget()` returns null instead of `{}`; grants receive ctx per call (rejects holding `combat`). All internal; no behaviour change.
- **Drone-readiness:** dict switch and ledger rows verified on master. The issue-cited `effect_context.gd:12` TODO is already gone (spec says so). Spec's test paths are wrong in one place: `test_stat_grant_routes.gd` lives in `test/unit/stats_system/`, not `test/unit/effects/` (drone will find it). Shadow/clone path (#506 `StatBoard._localized`) is the subtle bit; guarded by existing tests, and the spec says stop and report on any semantic test edit. Good.
- **Rec:** READY. Sonnet is probably fine; clone_for is the only subtle part.

### #580 Extract `Emissive.raw_lift` (dedupe edge/menu-edge colour lift)
- **What:** move the duplicated hue-preserving floor-lift math from `Edge._display_color_lifted` and `MenuEdgeView._lifted` into `Emissive.raw_lift(c, chroma_stops)`; add one sentence to the hdr-color rule.
- **Why now / value:** two copies of the same bloom math plus a long essay comment; dedupe.
- **Size:** s, 5 files (emissive.gd, edge.gd, menu_edge_view.gd, hdr-color.md, new test).
- **Calls baked in:** home = `Emissive` (first choice in issue's own preference list), tentative name/signature, rule file gets one sentence (it is an always-on rule, so it taxes every session by a line).
- **Drone-readiness:** verified both copies of `minf(c.r, minf(c.g, c.b))` exist (edge.gd:286, menu_edge_view.gd:190), `raw_lift` does not, and the named existing tests exist. (Also a third similar-looking median in identity_badge.gd:235; unrelated, spec doesn't touch it.) Acceptance 3 ("doc contains both numbered reasons + #413 provenance") is checkable by eye only. Golden-values test must be hand-computed from the old formula; fine.
- **Rec:** READY.

### #471 Make `VisionCircles` exact grid scale with owned count (finer, classified cells)
- **What:** rewrite the index inside `systems/vision_circles.gd` (finer grid; cells classified FULL/EMPTY/PARTIAL at build time), keep API and exactness; add randomized brute-force test; update bench header.
- **Why now / value:** perf finding: visibility pass is 6.1x slower at 200 owned vs 10 owned (bench header verified on master, 741 -> 4543 us), cell = max radius is the cause.
- **Size:** m, 3 files, but algorithmic.
- **Calls baked in:** technique is "the drone's call" within bounds; spec only gives a tentative recommendation (FULL/EMPTY/PARTIAL cells, cell ~ R/4..R/8). Target "under 2x at 200 owned" is a perf number the drone must hit by measuring.
- **Drone-readiness:** premise verified (`_cell_size = max(_max_radius,1)`, `_MAX_CELLS_PER_AXIS=128`, both existing tests and bench_fog_refresh_cost exist). Risks: `_build_index` reruns after every `add`, so build cost can eat the win (spec flags it); acceptance depends on running benches (needs real hardware; cloud CPU numbers differ, and RX 7900 XTX is irrelevant, this is CPU); exact-rim / cell-border float semantics are easy to get subtly wrong (the red-first exactness test is the guard). Open-ended optimisation with a numeric goal, not a mechanical edit.
- **Rec:** READY-after-tweak: mark it Opus-tier (or accept Sonnet may report "tried, hit 2.6x"), and say a PR that is exact but only partly hits the target is acceptable. Otherwise fine.

### #721 Retire LobbyScreen's before-_ready contract; author lobby_screen.tscn
- **What:** split `LobbyScreen._ready` into roster-independent setup plus a new `refresh()` that the panel calls after `add_child`; create `lobby_screen.tscn`; `LobbyPanel` instances it.
- **Why now / value:** last code-composed player-facing screen (scene-composition rule); unblocks a clean .tscn.
- **Size:** l, ~8 files (lobby_screen.gd/.tscn, lobby_panel.gd, 3 unit tests (~8 `LobbyScreen.new` sites), integration test).
- **Calls baked in:** `configure()` stays, pure data; screen scene root = VBoxContainer; refresh() idempotence only as far as tests need; 1031-line decomposition out of scope; start button moves into the scene (changes `add_option` code path).
- **Drone-readiness:** premises verified: `LobbyScreen.new` used in lobby_panel.gd:68 and 8 test sites, no `lobby_screen.tscn` yet, `control-composed` lint markers at lobby_screen.gd:88,219,226,242,245,616. Risks: it is the shipped online path (needs `mp:e2e`, ~30s, in acceptance, good); ordering gotcha (`_mount_link` before rows) is documented; the 1031-line screen with many `_ready` side effects is easy to regress; ~4 hours of Sonnet-work. Acceptance is concrete.
- **Rec:** READY-after-tweak: consider an Opus drone or a split (scene authoring + refresh() first, test migration second). Otherwise spec is sound.

### #855 Delete the GDScript per-substep contact/strain pass in BladeObstacleField
- **What:** delete ~200 lines (`begin_sample`/`after_drivers`/`project`/`restitute`/`end_substep` + scratch dicts) that mirror the C++ `FieldCtx`; re-point the one test helper `_sense_once` onto the native path.
- **Why now / value:** removes a parallel mirror (`no-parallel-mirrors` rule) with no parity test left to catch drift.
- **Size:** m, 4 files (blade_obstacle_field.gd, test_blade_swing_drag.gd, blade_sim.gd comment, blade_solver_native.cpp comments).
- **Calls baked in:** item 3 resolved as: `_near`, `_contact_*`, `_recoil` die as per-substep scratch; `_incident/_hops/_driven*` stay (drone re-greps each). `_sense_once` goes through the native solver, so the test now REQUIRES the native library; fallback to Bank-history assertions if a gap isn't visible after one step. C++ file touched for comments only.
- **Drone-readiness:** premises verified: the four methods and `_near`/`_contact_*`/`_recoil` still live on master, only caller is `test_blade_swing_drag.gd:436` (`field.project`). **Stale/wrong acceptance: `test_blade_goldens.gd` does not exist on origin/master** (no "golden" file in the tree), so "unchanged" is vacuous; drone should be told what guards trajectories (the full `test/unit/attack/` dir). Cold drone needs native lib built (spec says so, vaguely: "use `mise run` build task"; name it). Risk of silent behaviour drift is mitigated by deleting only code with no callers.
- **Rec:** READY-after-tweak: fix the goldens reference and name the native build task.

### #986 Fix flake in test_wire_outlives_the_level.gd:321
- **What:** raise the 2.0s `wait_until(root.is_reveal_ready)` budget to ~15s (and the identical helper in test_link_mount.gd), or tighten before/after if a sibling leaks.
- **Why now / value:** a flake that blocks `mise run land` on integration-tier branches.
- **Size:** xs, 1-2 files.
- **Calls baked in:** hypothesis that it is wait budget, not leaked state (reasoned from sharding being separate processes). Allows touching test_link_mount's identical helper. "No retry wrapper, no weakened assertion".
- **Drone-readiness:** line 321 and the 2.0 s waits verified (also `_wait_for_reveal` in test_link_mount.gd). The acceptance "10 consecutive green integration runs" is expensive (the tier is minutes each) but that is the issue's own bar. Reproduce-under-load step is vague about how, and a flake can't be proven fixed by 10 runs; accept as evidence. Drone must not claim cause without evidence ("say which of (a)/(b)").
- **Rec:** READY.

### #1214 GraphMirror.flip_pairs seam (GateFlipInstance stops poking astar)
- **What:** add `GraphMirror.flip_pairs(gates)` returning the toggle record; `nodes_islanded_by_flipping` and `GateFlipInstance._land_shadow` both go through it.
- **Why now / value:** topology should move only via a mirror method; removes a duplicated toggle loop. Pure refactor.
- **Size:** xs-s, 3 files (graph_mirror.gd, gate_flip_instance.gd, test_graph_mirror.gd).
- **Calls baked in:** return type = record of (a, b, was_connected) toggles plus an undo method, left to drone ("either shape acceptable"); otherwise as the issue says.
- **Drone-readiness:** premise verified exactly: duplicated loop in gate_flip_instance.gd:70-80 pokes `mirror.astar` and graph_mirror.gd:322-350 has the same toggle/restore loop. Characterization tests exist (test_gate_fuse, test_gate). Clean, small, behaviour-preserving, red-first test specified.
- **Rec:** READY.

### #1216 Gate confirm: Esc / right-click disarms it (ArmedMode level)
- **What:** new `GateConfirmMode extends ArmedMode` pushed on the armed stack when the gate-toggle confirm arms; Esc/right-click pops it and clears pending state.
- **Why now / value:** UX consistency: every other arm pops on Esc/right-click, the gate confirm doesn't.
- **Size:** s, 3 files (new gate_confirm_mode.gd, player_input_controller.gd, test_gate_toggle_input.gd).
- **Calls baked in:** a UX call: level is pushed ON TOP of whatever is current (including an active attack plan); it consumes no clicks; no badge/tint/icon; confirm is a panel, not a modal. Idempotent `on_popped` calls back into controller. Possible oddity (pressing the gate key mid-attack-plan) is explicitly parked, not solved.
- **Drone-readiness:** premises verified: `_request_gate_flip` / `_disarm_gate_confirm` (PIC:1571/1607), shared `pop_armed_level` (851), `ArmedStack.find/push/pop` exist, no `GateConfirmMode` yet. One imprecision: spec says the ctor is "like `CancelChannelMode`", but that extends `ManageVerbMode`; the base `ArmedMode` has `ctl` field and `on_pushed/on_popped`, so drone just sets `ctl`. `armed_stack.find(GateConfirmMode)` relies on `find(type)` taking a script; fine. Recursion guard specified. Tests concrete.
- **Rec:** READY (owner only needs to be fine with push-on-top/no-badge defaults).
