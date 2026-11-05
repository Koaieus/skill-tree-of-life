Checked against origin/master (fetched). master `SaveFile.FORMAT_VERSION` = 12, `MIN_FORMAT_VERSION` = 12.
SAVE COLLISION: #1415 and #1579 BOTH hardcode "FORMAT_VERSION := 13" (#1415 also MIN := 13; #1579 leaves MIN 12) and each pins its own row_layout_hash in test_save_file.gd. Whichever lands second must be 14 and re-pin; run them serially, and the second drone's brief needs "bump from whatever master holds", not "13".

### #1242 Volatility colour on owner_panel scalar rows + CombatValueRow
- **What:** pass `board.is_stat_volatile(id)` into `bind_scalar` in OwnerPanel (one line); make CombatValueRow re-check volatility when a modifier flip leaves the value unchanged or a formula crosses zero.
- **Why now / value:** closes a #1239 follow-up; violet "volatile" tint is wrong/missing on two surfaces.
- **Size:** s; 3-4 files (owner_panel.gd, combat_value_row.gd, maybe stat.gd, 1-2 tests).
- **Calls baked in:** none (body acceptance is the owner's). If a new Stat signal is needed it is a small new public API ("volatility-changed").
- **Drone-readiness:** Premise holds: owner_panel.gd:156 still `bind_scalar(def, values[i])`; row recomputes `value_volatile` only in `_on_stat_changed`, which hangs off `value_changed`. Half 1 is trivial and concrete. Half 2 is open-ended ("pick the narrowest trigger", unknown whether a signal exists), and a red test for "value unchanged" may be hard to write. Path correction already in spec. Risk of a drone sprawling into stat.gd.
- **Rec:** READY (suggest: if the row fix needs a new Stat signal, stop and report rather than add one).

### #1415 Rename tempo stat -> momentum
- **What:** rename the kill-AP-refund stat id/def/board export/loot method/tests/docs from `tempo` to `momentum`; leave all animation-pacing "tempo" alone.
- **Why now / value:** owner OK'd 2026-10-05; frees "tempo" as the design-axis word.
- **Size:** m; ~14 files (def move, roster, entity_stat_board.gd, default_entity_board.tres, loot_system.gd, save_file.gd, 2-3 tests, 4 docs).
- **Calls baked in:** (1) bumps FORMAT_VERSION and sets MIN_FORMAT_VERSION := 13, i.e. REFUSES every existing save/older file instead of an alias or migration; spec itself says "the one thing to confirm at review". (2) Player-visible strings: display name "Momentum", modifier_name "Max Momentum / turn". (3) Kill-switch knob renamed `award_tempo_on_kill` -> `award_momentum_on_kill` (no scene sets it).
- **Drone-readiness:** Premise holds (tempo.tres, `pool_tempo`, test_loot_kill_tempo.gd all exist; no existing `momentum` stat, only unrelated blade-sim locals). Hardcodes 13 (see collision above). tempo.tres has no `uid=` in its header, so "keep uid so refs survive" is vague; the roster/board reference it by path. "Do NOT touch" list is good but grep of leftovers (composite_bar_gauge, melee_body, minimap layer mention tempo) needs the drone to judge animation-vs-stat; acceptance 2 grep handles it. Needs mp:e2e.
- **Rec:** READY-after-tweak: owner decides refuse-old-saves vs alias; change save wording to "bump to next free version".

### #440 Per-repaint quadratic walk in melee (and ranged) attack plans
- **What:** make `MeleeAttackPlan._is_neighbor_of_blade_set` stop walking `graph.get_edges()` per node; confirm ranged is not a problem.
- **Why now / value:** perf debt, no profile showing it matters; issue carries `stale?` label and an owner "stale?" comment.
- **Size:** s; 2-3 files (melee_attack_plan.gd, new test, maybe ranged).
- **Calls baked in:** scope narrowed to melee only; ranged declared non-problem (verified: ranged get_node_role calls get_firing_positions once per node = one mirror query) and left untouched unless measured. Owner never answered "stale?" and spec answers it on its own authority.
- **Drone-readiness:** Melee premise TRUE (predicate at melee_attack_plan.gd:1625 still loops `graph.get_edges()` per node). But the spec's cleaner pick `GraphMirror.are_adjacent` returns false when either endpoint has no vertex_id, and the code comment says candidates are not yet in the mirror, so the primary pick is probably wrong; the cache fallback is the real path. Simpler option the spec missed: `graph.get_neighbours(node)` is cached O(degree) (graph.md says use it instead of hand-rolled edge walks). "Drone picks by testing" is acceptable but wastes a cycle. Acceptance 3 (measure ranged over 800 nodes) is soft.
- **Rec:** READY-after-tweak: name `graph.get_neighbours(node)` as the first pick; or CLOSE if the owner doesn't care about perf without a profile.

### #442 AllocationVFX code-composed trees -> scenes
- **What:** move the alloc spike, dealloc lift, pop burst and the nested `_SnapshotDisk` class into 4 scenes + scripts under `ui/vfx/allocation/`; consts become `@export`s; the public statics keep their signatures.
- **Why now / value:** editor-previewable/tunable VFX, visible to bloom migration; house scene-composition rule.
- **Size:** m-l; ~10 files (allocation_vfx.gd, 4 new .tscn + 4 .gd, a doc line, 1 new test).
- **Calls baked in:** shatter portion dropped as already done (verified: ShatterField scene exists; no per-node 48-tween build in master); scene names and folder; tuning consts become exports (inspector-editable); Tween kept in script (AnimationPlayer conversion parked); header says "five trees" but 3 converted + 1 class, so issue title is now inaccurate.
- **Drone-readiness:** Premise holds (allocation_vfx.gd 716 lines on master, `Polygon2D.new`, `CPUParticles2D.new`, `Gradient.new`, `class _SnapshotDisk` all present; statics used by menu_node_view and 3 tests). Acceptance 3 says no `Polygon2D.new()` but the same spec says the needle is "still built in code": mild contradiction (polygon data vs node). "Visuals must look identical" is unverifiable by a headless drone (needs human eyeball in dev_sandbox). Position-doubling trap is called out. Good tests.
- **Rec:** READY (owner eyeballs the visuals after merge).

### #335 Split SkillNode.modifiers into authored_modifiers (@export) + runtime modifiers
- **What:** add `@export authored_modifiers`, make `modifiers` non-serialized runtime array; re-point procgen/sandbox/balance writers and 11 authored scenes; remove the editor-hint guards in `_attach_addon`/`_detach_addon`; trim the skill-node-addons rule.
- **Why now / value:** closes the compounding-on-save hazard; retires the #334 stopgap guard.
- **Size:** l; ~35-45 files (skill_node.gd, node_state, procgen, 2 sandbox panels, balance_scenarios, 11 scenes, rule file, ~20 test files that assign `node.modifiers = [..]`).
- **Calls baked in:** property rename on a core class with silent-drop risk on old files; "seeded in _ready" design; optional rewrite of graph_snapshot encode side (spec says only if trivially equivalent); leaves wire format and FORMAT_VERSION alone.
- **Drone-readiness:** Premise holds (`@export var modifiers` at skill_node.gd:112 backed by state.modifiers; `add_entity_modifier` does `modifiers.append(m)`; 11 scene files + procgen/sandbox writers match). Risks: (a) the spec says "seeded from authored_modifiers" but not "duplicated": if seeded by reference (and NodeState.clone copies by reference) addon grants append into the authored array = the exact bug; (b) hottest file, conflicts with #1145 and #1579 (all edit skill_node.gd, serialize them); (c) the serialization test (acceptance 2, `PROPERTY_USAGE_STORAGE` check) is feasible but the "simulate editor hint" case is admitted impossible; (d) ~20 test files to repoint is a lot for one sonnet unit. Needs mp:e2e.
- **Rec:** READY-after-tweak: add "seed by duplicate, never by reference" and consider splitting tests/sweep; or run with an opus drone. Sequence after #1145/#1579.

### #1124 FanAnchor._route drops `shoulder`
- **What:** thread the trace's `route_params()` dict through solve_route -> derive_anchor core -> `_route`, keep `derive_anchor` as a thin wrapper for bare-arg tests.
- **Why now / value:** preventive; harmless today by the issue's own admission.
- **Size:** xs-s; 2 files (fan_anchor.gd, test_fan_anchor.gd).
- **Calls baked in:** none (settled by "design look" answered inside the spec; wrapper kept; owner's 2026-10-14 triage is only "Backlog").
- **Drone-readiness:** Premise holds: `_route(from,to,trunk_dir,trunk_frac,trunk_px)` has no shoulder arg; `solve_route` already takes `params` (so the dict is half-threaded already); `shoulder` exists on FanTrace. Red-first is weak: spec admits no geometry may differ today and provides a fallback assert. Fine for a refactor, existing test_fan_scene guards.
- **Rec:** READY (low value; fine as filler, or CLOSE if you'd rather not carry dormant-bug fixes).

### #1145 NodeFeedback: extract hit-flash/blink/shake from skill_node.gd
- **What:** new `NodeFeedback` child node (skill_node/node_feedback.gd, instanced in skill_node.tscn) owning the three tweens + `reset()`; SkillNode keeps one-line forwarders.
- **Why now / value:** shrinks the hottest file; #426 seam.
- **Size:** s-m; 4 files (skill_node.gd ~-90 lines, node_feedback.gd, skill_node.tscn, test_dealloc_denied_feedback.gd).
- **Calls baked in:** resolves the body's "child node or presentation/ presenter" hedge as a child node of skill_node.tscn (spec flags it tentative); edits skill_node.tscn, which every one of ~233 instancers inherits; knobs moved verbatim.
- **Drone-readiness:** Premise holds (play_hit_flash/_reset_feedback/blink_blocked/shake_denied still in skill_node.gd at ~1950-2014; spec's line numbers drifted ~15). Only one characterization test, no new test (body says visual work, no test); a tween regression would be caught only by eye. Wiring `_addons` via Callable is a bit hand-wavy but workable. Rebase conflicts with #335/#1579.
- **Rec:** READY (merge before #335).

### #1579 Remove the status-tag channel
- **What:** delete add_tag/remove_tag/has_tag/get_active_tags, `grant_tag`, TagAuraEffect, `_R_TAGS` restore, tag-only tests; reserve snapshot slot 8; bump FORMAT_VERSION; fix 2 docs.
- **Why now / value:** removes dead code with no shipped consumer; owner chose removal over an ADR (2026-10-12).
- **Size:** m; ~20 files (3 deletes + tests, effect_context/instance, node/entity combat, skill_node, entity, 2 states, entity_snapshot, save_file + test pin, 3 test edits, 3 docs).
- **Calls baked in:** (1) retires #240 (LifeLine grace) and #738 as dependent; spec only flags them, not closing them; (2) slot 8 left reserved/null, MIN_FORMAT_VERSION stays 12 so v12 files still load (differs from #1415's refuse-old-saves); (3) rewrites the lifeline-grace.md banner.
- **Drone-readiness:** Premise holds: no `.tres`/`.tscn` references tags; the grep list on master matches the spec's file list exactly (plus procgen tag_registry, intentionally kept). Hardcodes 13 (collision above). Needs mp:e2e. Old v12 files with populated slot 8 must still decode; acceptance 2 covers it. Deletion with a hard grep gate is cold-drone-friendly.
- **Rec:** READY-after-tweak: change "12 -> 13" to "bump to the next free version" (or land before #1415 and tell #1415 to take 14).

### #347 SkillNode lab: entry point, live sync, readouts (older spec, 2026-09-14/15)
- **What:** add an `@export_tool_button` on SkillNode (new "Lab" group) that opens `skill_node_lab.tscn` in the editor, verify inspector edits redraw live, and add text readouts (allocated N/M, archetype, local modifiers) to the lab scene via a small @tool script.
- **Why now / value:** editor DX for authoring/verification.
- **Size:** s-m; 4 files (skill_node.gd, skill_node_lab.tscn + new script, sandbox-framework.md).
- **Calls baked in:** opens lab in the 2D editor (not a sandbox-host tab); readouts live IN the lab scene (owner's last comment said live UI inside the inherited scene is "annoying (needs another editorplugin so nahh)" and also floated a "select scene" button in the sandbox tab; spec picked neither exactly); auras/effects readout dropped (deferred to #259).
- **Drone-readiness:** Still mostly current: lab scene exists, no open-lab button yet, `skill_node_lab` referenced only by node_visuals_panel.gd. Drift: spec says "file has no @export_group yet"; master now has `@export_group("Bench")` (skill_node.gd:245-262) and the tool button is now at line ~177, not 118, so the line refs are stale (idiom is the same; `Engine.get_singleton(&"EditorInterface")` precedent exists in 3 files). The lab is instanced 5x in node_visuals_panel, so readouts appear 5 times in that tab; the spec notes it but doesn't say whether that's acceptable. Acceptance needs "a screenshot in the report" and manual editor checks, which an unattended drone cannot produce; no test. Owner's last comment conflicts with the chosen approach and is not explicitly answered.
- **Rec:** NEEDS-DESIGN (cheap): reconcile owner's last comment (live readouts in the inherited scene vs sandbox-tab button) and the 5x-instancing clutter; the tool-button half alone is READY.
