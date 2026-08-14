# Audit triage — 2026-08-14

Consolidates the ~167 findings in the 8 slice reports into four buckets.
Read this instead of the 8 reports; each row cites its report + finding number.

- **A — Apply directly.** Unambiguous, file-disjoint, no design fork. No ask.
- **B — Ask the owner.** Genuine design forks. Deliberately short (8 items).
- **C — File as issues.** Structural work under one hub.
- **D — Still open.** Not audited, not fixed.

Status column: `todo` / `done <sha>` / `issue #n`.

---

## A — Apply directly

Batched file-disjoint. Each batch: edit → `mise run check` → `mise run test` → commit.

### A0 — Owner-reported live bug, 2026-08-14 (not from the audit)

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A0.1 | `ui/fog_overlay/fog_overlay.gd:201` | `vision_visible` was ANDed over both endpoints, so an edge with one endpoint in vision range and one outside landed in `VIS_HIDDEN` → `edge_mesh.gdshader:70` hard-zeroes alpha → **a visible node draws with no connecting edges.** The sensed channel doesn't cover it either (`vision_system.gd:355` requires *both* endpoints reached). Changed to OR; #413's `VIS_VISIBLE` branch already fades per-fragment. | owner report | **done 895fd55** |

**Open follow-up on A0.1 (owner's call, needs a windowed look).** The far half
of a straddling edge now dims to `_VISIBLE_DIM_FLOOR = 0.30` rather than to
zero — that floor exists so a *fully visible* edge doesn't bisect into black
mid-fade, and it is arguably wrong for a straddling one. It leaves a faint stub
terminating at the fogged node's rim. Mitigating factor: the fog quad sits at
z=1000 and the edge at `ZLayers.EDGE = -10`, so it draws *under* the fog. If the
stub reads as a topology leak in-game, make the floor conditional on a new
straddle vis-state in `edge_mesh.gdshader`. **Not headless-verifiable.**
**Filed as #418.**

### A1 — Owner smell #2 + #3 (the render/build bugs)

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A1.1 | `graph/edge.gd:364` | `_draw_self_loop` calls `_display_color` (SDR-only per its own docstring); switch to `_display_color_lifted` so the `pow(2, lit_glow_stops)` HDR lift applies. **Not headless-verifiable** — see note below. | graph-core #2 | **done 2945015 — VISUALLY VERIFIED** |
| A1.2 | `graph/edge.gd:113` + `ui/fog_overlay/fog_overlay.gd:196` | `sensed` promotes to `ZLayers.EDGE + ZLayers.SENSED` = 991, *below* FogOverlay at 1000. Promote to the absolute `ZLayers.SENSED` band. Add an assertion on the promoted value to `test_edge_z_order.gd:52`. | graph-core #3 | **done 2945015** |
| A1.3 | `addons/spell_playground/playground_panel.gd:200` | `_build_grid_edges` bails on `if not graph.get_edges().is_empty(): return`, so one authored self-loop suppresses all 24–27 generated edges. Make the guard per-pair, or author the edges into the `.tscn`. | graph-core #1, devtools #1 | **done 07868a5** (authored into the .tscn) |

**A1.1 VERIFIED 2026-08-14 — smell #2 is closed.** Measured on a real
renderer (`Xvfb :99` + `--rendering-driver opengl3`, `dev_sandbox.tscn`, whose
WIP self-loop on `Down_Out` is the repro), sampling the ring's pixels with the
lift reverted vs. applied:

| | mean | max |
|---|---|---|
| `_display_color` (SDR, before) | 0.055 | **0.592** |
| `_display_color_lifted` (after) | 0.101 | **1.000** |

Before, the ring's brightest pixel never reached 1.0, so `glow_hdr_threshold`
could never fire — it rendered as a dim olive circle. After, it clips at 1.0 and
the regional mean nearly doubles, which is the bloom halo spreading energy into
neighbouring pixels. Visually: muddy dark-olive → saturated gold with a halo.

This also answers the open question about whether the lift survives at all on
this path: `_display_color_lifted`'s docstring derives everything from
`set_instance_color` carrying no `source_color` hint, but `draw_arc` pushes its
`Color` through the canvas item's **vertex colour** attribute instead — a
different pipeline that could have clamped `pow(2, 4.5)` at submission. It does
not.

### A2 — Red-master repairs (make the gate meaningful)

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A2.1 | `skill_node/visuals/node_visuals_composite.tscn:19-36`, `rim_ring.tscn:6-12`, `node_visuals_panel.tscn:91-96` | Delete every `instance_shader_parameters/*` line. Scene instantiation applies them by name via `set()`, which `_validate_property`'s STORAGE clearing does not intercept — so every node claims slots in the 4096-item global instance-uniform buffer from load, defeating the `is_visible_in_tree()` fog gate (the #172 regression, verbatim). Then extend `test_disk_and_rim_ship_no_baked_material` to assert on instance params, not just `material`. | skill-node #2, #3 | **done f69c7df** |
| A2.1b | `skill_node/visuals/` — site TBD | **Scope correction, measured 2026-08-14.** `test_node_visuals_contract` fails **three** test functions, not two. A2.1 covers only the two `assert_null` instance-uniform ones (`test_fog_hidden_composite_registers_no_instance_state`, `test_unfogged_composite_syncs_on_becoming_visible`). The third, `test_rim_tint_mix_tracks_allocation:125,127`, is a **separate, undiagnosed divergence**: `tint_mix` reads 0.8 where the test wants 0.3 ("unallocated rim reads mostly bronze metal") and 0.9 where it wants 1.0 ("allocated rim reads full archetype tint"). No auditor reported this — likely the composite's `FILLED_TINT_MIX`/`UNFILLED_TINT_MIX` swing (cf. skill-node #11). **A2.1 alone will not turn this script green.** | measured | **done 9aeb22b** — owner confirmed the colourful swing is intended and required for legibility; the TEST was stale, not the code. #419 closed. Master 6 red -> 5. |
| A2.2 | `test/unit/ui/test_fan_scene.gd` | Known-broken, parked in FOCUS lane E item 7 while still collected. Mark `pending("#<n>")` so the baseline is green and new red is unambiguous. | test-infra #2 | **done f69c7df** (#362; `pending()` does not short-circuit in GUT — needs an explicit `return`) |
| A2.3 | `test/unit/test_tooltip_v2_accessors.gd:178` | **The sixth red, missed by every auditor and by this doc's first pass.** `test_spike_ring_keeps_its_authored_title_and_payload` asserts one modifier; #406 (`db9a0a2`) gave Spikes a second (flat +3 alongside the ×1.5) and never updated it. Both are authored payload — assert both. Same commit, same file as A3.3/A4.12; landed together. | measured 2026-08-14 | **done b1a79f3** |

`test_spell_defs::test_reverberator_preset_well_formed` is **not** here — it is a
content fork, item B1.

**Master red: 6 → 1.** The only remaining failure is B1/#417, blocked on an open
owner design fork. `test_fan_scene` is `Pending`, not passing — #362 is still a
real bug, just no longer masking new red.

### A3 — Live bugs, no fork

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A3.1 | `systems/allocation_system.gd:96` | `register_scene_authored_ownership` omits `node.apply_entity_modifiers_to(board)` that both `allocate()` and `force_allocate()` call — so **every hand-authored owned node's modifiers are inert**. `dev_sandbox.tscn`'s `Right`/`Down` grant the player nothing. Add the call + a pinning test. | systems #1 | **done 0627c76** — also reordered the body to match the other two paths (fill LAST, so the #376 mutator finds the grants). **Checked and cleared:** the same function also skips `navigator.mirror_add`, which looks like the identical bug — it is not. `EntityNavigator._ready` → `GraphMirror.wire_to` bootstrap-sweeps already-owned nodes. Pinned in the same test so nobody re-opens it. |
| A3.2 | `procgen/playground/node_graph_view.gd:288` | `_archetypes[idx].color` — `ArchetypePolicy` has no `color`; every `_draw` after a stamp throws. Paint Mode (the #166 headline feature) is broken on first repaint. Use `.archetype.color` with a null guard. | procgen #6 | **done f93bb51** |
| A3.3 | `skill_node/addons/spike_ring_addon.tscn:16` | `Resource_u38nb` (blade_damage ADD_BASE 3.0) lacks `resource_local_to_scene = true`, so **every** SpikeRingAddon shares one instance and the #376 mutator's live `m.value` write rewrites spike damage board-wide. Add the flag + a test walking `skill_node/addons/*.tscn`. | skill-node #7 | **done b1a79f3** — confirmed real; the walk-test asserts by instance identity and was verified red first. `.claude/rules/godot-scene-authoring.md` already *claimed* these scenes all set the flag, so the rule was lying too; it now cites the test. |
| A3.4 | `ui/vfx/coordinator/magic_bounce_coordinator.gd:103` | `play()` starts `_play_three_clocks()` without awaiting and drains on `pending[0] > 0`, so it can return mid-timeline and `AttackVFX.play` frees the coordinator — later beats and their `take_damage`/`heal_damage` lambdas never run. `await` the clocks; seed `pending` with the total event count up front. | vfx #3 | **done** — `await` added; `pending` NOT reseeded (the per-spawn increments have early-return holes that a precomputed total would desync). Pinned deterministically via a beat-0 that spawns nothing (null `cancel_visual`) rather than the `interval > 2*flight` race, which loses to projectile linger. `.claude/rules/spell-vfx.md` already stated the drain is teardown safety, not a wave gate — the code just didn't do it. |
| A3.5 | `ui/floating_number_layer/strikethrough_toast/strikethrough_toast.tscn:9` | `gray_amount = 1.0` / `strike_x = 0.558` are mid-animation values serialized back into the scene; every removed-modifier toast plays backwards for its first 0.2 s. Reset to 0.0 and set explicitly in `_ready`. | vfx #13 | **done f93bb51** — also set in `_ready`, so a round-trip can't re-bake it |
| A3.6 | `addons/spell_playground/playground_panel.gd:306` | `"%.3s" % v` is a *string* precision spec on a float — `12.5` prints `12.`. Use `"%.3g"` (the vfx playground's copy is already correct). | devtools #10 | **done f93bb51** — **the triage row was wrong**: the vfx playground's `%.3g` is NOT correct, GDScript's `%` has no `g` conversion and it was pushing "unsupported format character" on every float. Both copies now use `String.num(v, 3)`. |
| A3.7 | `skill_node/visuals/node_visuals_composite.gd:303` | `geom_crest_r` is stored and never forwarded — `_sync_stake()` never writes `crest_r`, so every in-game rim runs at the authored `0.0`, outside its own documented range. The #341 legibility sweep was judged against a rim the game does not render. | skill-node #6 | **done f93bb51, corrected 2026-08-14** — the forward is in and the value is UNCHANGED, so it lands pixel-neutral. The first attempt raised it to 28.0 citing `skill_node_lab.tscn`'s authored 36/40/44; that was bad evidence — the lab sets `geom_crest_r` on the *composite*, i.e. the very export that was inert, so its value never rendered either. `node_visuals_panel.tscn` (where #341 was actually eyeballed) instances `rim_ring.tscn` and therefore rendered 0.0 like everything else. What crest_r should be is **B9**. |

### A4 — Correctness cleanups (mechanical)

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A4.1 | `graph/graph_mirror.gd:127` | `get_nodes_by_degree` reads bare `astar.get_point_connections().size()` while `get_degree` adds `2 * self_loop_count` — two degree definitions in one class, and `.claude/rules/degree.md` names `get_degree` canonical. Call `get_degree(node)`. | graph-core #6 | **done** — behavioural, not cosmetic: a self-looped node reported one degree to `get_degree` and another to every degree QUERY, so `RangedAttackPlan`'s `get_leaf_nodes()` treated it as a leaf. Red-green pinned. |
| A4.2 | `graph/graph_mirror.gd:48` | `mirror_add` scans all of `get_edges()` per node → O(N·E) at load and a fresh O(E) on **every allocation**. Use the cached `graph.get_neighbours(node)`. | graph-core #7 | **done** |
| A4.3 | `systems/allocation_system.gd:427` | `_real_neighbours` hand-rolls an edge walk; `graph.get_neighbours()` is the cached index. Keep the `n != node` self-loop filter. | systems #17 | todo |
| A4.4 | `systems/allocation_system.gd:489,498` + `ui/.../node_highlight_overlay.gd:65` | `can_allocate` is O(N+E) and the highlight overlay calls it per node → O(N·(N+E)) per repaint, re-fired on every alloc/dealloc/SP change. `_has_any_owned_node` → `entity.navigator.get_mirrored_nodes().is_empty()`; adjacency → `get_neighbours`. | systems #4 | todo |
| A4.5 | `systems/player_input_controller.gd:582`, `systems/battle_system.gd:155,161` | AP/mana gates read `.current`; `.claude/rules/stats-system.md:144` requires `available()` and *names these files as compliant examples* — the rule file is currently lying. Switch all three, correct the rule. | systems #6 | **done** — plus **two sites the triage missed**, `ui/hud/action_cluster/action_cluster.gd:95,112`. Behaviourally inert today (`action_points`/`mana` are plain pools; only `deallocation_points`/`movement_points` carry a surplus bin) — which is precisely why it went unnoticed, and why `allocation_system.gd:297` reading `action_points.available()` sat next to three siblings that didn't. Rule corrected with the reason. |
| A4.6 | `archetypes/archetype.gd:24` | `color` getter does `StatRegistry.get_def(primary_stat).tint_color` unguarded on a `@tool` script — a typo'd id takes the editor down on a property *read*. Null-guard + `push_warning`. | graph-core #12 | todo |
| A4.7 | `attack/range_finder/range_finder.gd:54` | Base `gather()` writes `0.0` for every node while its docstring promises the distance that feeds `DistanceScale`. Make it `@abstract` (both concretes override) or return `-1.0`. | attack #10 | todo |
| A4.8 | `skill_node/skill_node.gd:1409` | `can_attach_addon` calls `get_addons().size()` — duplicates the whole ledger to count it, per candidate node in the #406 UI. Use `_addons.size()`. | skill-node #20 | todo |
| A4.9 | `systems/loot_system.gd:163-165` | `_removed_this_attack` is cleared only under `if battle_system != null` but read unconditionally, so an unset export makes kill XP count earlier attacks' territory at bonus rate. Also clear in `_on_entity_dying` after payout. | systems #9 | todo |
| A4.10 | `ui/vfx/coordinator/magic_bounce_coordinator.gd:189` | `_play_cancel` writes `global_position` on an untyped `Node`; a `Control`-rooted override crashes. Cast `as Node2D` + guard. | vfx #22 | todo |
| A4.11 | `effects/core_aura.gd:27` | `@export var range: float` shadows GDScript's built-in `range()` in the class and every subclass. Rename to `hop_range`. | vfx #21 | todo |
| A4.12 | `skill_node/addons/spike_ring_addon.gd:19` | `spike_color` is a getter-only `@export` that the scene writes — the authored value is discarded and the inspector field cannot be edited. Drop `@export`, drop the scene line. | skill-node #19 | **done b1a79f3** (landed with A3.3 — same file) |

### A5 — Lies in comments, docs, and rules

Each of these actively misleads the next reader. All are delete-or-correct.

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A5.1 | `attack/spell/on_hit/healing_effect.gd:13` | TODO says nothing consumes `AttackOutcome.heals`; both `battle_system.gd:209-211` and `magic_bounce_coordinator.gd:173-176` do. Delete the TODO. | attack #12 | todo |
| A5.2 | `procgen/pools/stat_pool.gd:190` + class docstring + `docs/domain/procgen-v4.md` D9 | The debuff `max_tier > 1` validator contradicts a settled decision (`test_pool_seed_values.gd:99`, 2026-08-07) and trips on the repo's only debuff pool at every editor open — training designers to ignore procgen warnings. Delete the warning, fix both docstrings and the doc. | procgen #9 | todo |
| A5.3 | `docs/domain/allocation_system.md`, `loot-system.md`, `vision-system.md` | All three drifted: `allocated` is 3-arg with a `forced` flag; `deallocated` does *not* fire from the forced path (`force_deallocated` does); the loot trickle rides `battle_system.cascade_started`, not `Events.skill_node_destroyed`; vision doc says `get_local_stat`, code is `get_local_value`. These are the docs the brief hands new agents. | systems #15 | todo |
| A5.4 | `docs/domain/attack_plan_system.md:38,274,21` | Names `SingleHostileNodeTargeting` / `SingleAlliedNodeTargeting` / `get_highlight_role`; shipped names are `NodeTargeting` (one class, `ownership_filter` mask) and `HighlightProvider.get_node_role`. | attack #19 | todo |
| A5.5 | `procgen/graph_procgen.gd:888-914` | 27 lines of commented-out predecessor under a docstring promising "first-drawn order" while `get_aggregate()` sorts by descending cost. Delete the block, fix the sentence. | procgen #16 | todo |
| A5.6 | `addons/sandbox_host/sandbox_tab.gd:8` | Base-class docstring states the PLAYED/LIVE distinction *reversed by #260/#77* — the load-bearing concept of the framework, in the first file a tab author reads. Replace with the "auto-tick = played; explicit-step = live" kernel. | devtools #14 | todo |
| A5.7 | `tools/gen_sandbox_tabs.gd:15` | "How to add a tab" instructs authors to override `panel_scene` — the path `.claude/rules/sandbox-host.md` forbids. Rewrite around `%PanelHost` baking. | devtools #6 | todo |
| A5.8 | `skill_node/visuals/rim_bonuses.gd:170` | Asserts "no project-wide glow/bloom environment exists yet"; one has existed since #371. | skill-node #12 | todo |
| A5.9 | `autoload/events.gd:107` | `ai_decision` docstring says "zero consumers is a no-op"; it has 2. (Wider check: all 20 bus signals have production listeners — the brief's dead-signal hypothesis is **refuted**.) | graph-core #18 | todo |
| A5.10 | `ui/vfx/allocation_vfx.gd:326` | Comment describes a "glow ramp"; no glow term exists in the code. | vfx #7 | todo |
| A5.11 | `attack/plan/melee_attack_plan.gd:384-385` | Comment claims the method is shared with `MeleePreview`; `MeleePreview` calls `SkillBlade.build_from_skill_nodes` instead. (Comment fix only — the duplication itself is C-bucket.) | attack #1 | todo |

### A6 — Dead code

| # | Site | Change | Source | Status |
|---|---|---|---|---|
| A6.1 | `ui/floating_number_layer/floater.gd` + `.tscn` | Zero references since #81; 92 lines of a second differently-shaped floater. Delete + sweep `.uid`s. Also drop `FloaterStyle.float_distance` / `max_angle` (documented as unconsumed). | vfx #16 | todo |
| A6.2 | `procgen/graph_procgen.gd:1010`, `procgen/pools/modifier_pool.gd` | `_weighted_pick_from` (35 lines), `ModifierPool` (42), `ModifierPoolEntry.is_in_budget`/`has_weight` — zero production callers, kept alive by two tests while `_v4_weighted_pick` ships. Delete all four; re-point `test_weight_profiles.gd`. | procgen #12 | todo |
| A6.3 | `attack/spell/propagation/filter/max_visits_filter.gd`, `min_damage_reducer.gd`, `cancel_if_even_reducer.gd` | Zero consumers; `MaxVisitsFilter`'s rule is already enforced unconditionally by `spell_resolver.gd:124-129` and its `fallback_cap = 1` would *disagree* with a preset. Delete. Mark `CoreDistanceFilter`, `ExpressionReducer`, `RandomPickStep` as unshipped in their docstrings with the issue that will consume them. | attack #5, #15 | todo |
| A6.4 | `ui/aura_overlay/aura_overlay.tscn:8`, `ui/fog_overlay/fog_overlay.tscn` | Each serializes a dead 256-entry `shader_parameter/circles` array for a uniform neither shader declares since #177; the aura scene also writes `intensity` twice (0.6 then 0.15). Strip, `mise run refresh`, commit churn once. | vfx #17 | todo |
| A6.5 | `scenes/game_root.gd:270` | `_on_core_moved` matches an effect hook signature but `GameRoot` is not an `Effect` and nothing calls it — dead code shaped exactly like live wiring. | graph-core #21 | todo |
| A6.6 | `ui/theme/emissive.gd:116,136` | `tint_peak` / `tint_damped` self-labelled "CANDIDATE, not yet adopted anywhere" with 20 lines of docs each; four near-identical entry points, no rule for choosing. Move to `docs/domain/hdr-color.md`, delete from the class. | vfx #20 | todo |

### A7 — Typed collections + hygiene

Do these opportunistically when touching the file, except the four cross-boundary
contracts which are worth a dedicated pass:

- `systems/battle_system.gd` `signal cascade_started(layers: Array, …)` → `Array[Array]` (LootSystem hand-casts it today) and `AllocationSystem.reachable_core_landings() -> Dictionary[SkillNode, int]` — systems #18
- `attack/melee/blade_pop_resolver.gd` `Result.dead_at` — crosses into `MeleePreview._on_live_hit` untyped — attack #16
- `systems/player_input_controller.gd:67` temp-upgrade arm is `Variant` end to end, then does `.script` on it — systems #20
- `addons/sandbox_host/sandbox_host.gd:23` `_live_tabs` untyped → a `tab_id` typo is a silent no-op — devtools #20
- `addons/allocation_sandbox/…:311`, `addons/loot_sandbox/…:279` raw `PoolStat.base_value` writes → `set_base_ratcheted` (corrects the Phase-1 baseline: the grep missed `addons/`) — devtools #15
- Sweep 199 exact-float `assert_eq` → `assert_almost_eq` — test-infra #13

**Two brief metrics are false positives, discard them:** "26 missing `->` in attack"
and "22 in procgen" both counted multi-line signatures whose return type sits on
the closing-paren line. Genuine count in `attack/` is **0**; in `procgen/` it is
**1** (`stat_pool.gd:94 _update_resource_name`). — attack #20, procgen #20

---

## B — Ask the owner (design forks)

These eight are the only findings where a wrong guess is expensive. Everything
else is in A or C.

**B1 — Which Reverberator is the real one? → FILED AS #417.** Full fork,
the owner's reasoning and the primitive mapping now live on the issue; the copy
below is a summary. Owner is mid-design.
The `.tres` ships `TakeTopNStep(2)` + `MaxDamageReducer` +
`ScaledAddProgression(0.5)`; the player-facing `description` and
`test_spell_defs.gd:70-73` both say `SumDamageReducer` + `MultiplyProgression`.
All three diverged inside commit `aca098b`, titled as a `TakeTopNStep` refactor.
*(attack #3 — also the 6th red test)*

The owner's answer (2026-08-14) was not "restore one of them" but a live design
fork, recorded here so it isn't lost. **Do not edit `reverberator.tres` until
this settles.** Their framing:

> I doubt between having it 1) spread to all neighbors of equal or higher
> degree or 2) spread to all neighbors who have highest degree amongst them.
> The scaled add I'm not sure but I think it's better than the raw multiplier.
> And max damage reducer or sum add reducer depends on the first question — 1
> would fan out more and hence allow multiple incidents more often, having sum
> as reducer then would be overpowered; 2 would spread less and sum could
> be... well... still very strong. The perfect target is a node with
> self-loops: from there, the self-loop would add *2 outgoing targets in the
> spread* **which point at that very node** ***and crit doing so***. The doubly
> propagation-to-self would trigger the reducer too, so if we sum we'd
> effectively double the damage (and then still crit). Maybe too strong? Maybe
> just right? Or if we make the default scaling per hop low, it would deal fuck
> all damage to regular nodes but IF it reaches a node with a self-loop it will
> 100% kill it.

**Both options are already expressible with shipped primitives — no new
classes needed:**

- **Option 1** (all neighbours of equal-or-higher degree) = `DegreeFilter`
  with `Compare.GREATER_OR_EQUAL` + `FanAllStep`. The enum arm exists and its
  docstring already names it "climber".
- **Option 2** (only the joint-highest-degree neighbours) = `RankPass` →
  `TopTiesPass` with a `DegreeRanker`. `TopTiesPass.filter` keeps every
  candidate tying the max, so ties fan and everything else is dropped.
  *(`bruiser.tres`'s uncommitted WIP already gained an unused `rank_pass.gd`
  ext_resource — the owner was wiring exactly this.)*

**The self-loop reading is confirmed by the code, verbatim.**
`self_loop_crit_condition.gd`: "A self-loop edge node-fans two copies back at
itself; the resolver stamps `predecessor = current_node` on those hops."
`evaluate` is `state.predecessor == target`. So two copies land, both crit, and
`spell_resolver.gd:54` groups incidents by `SkillNode`, so both reach the
reducer in one merge. Sum → exactly 2×, then crit. Max → 1×, then crit.

**Two things the owner's sketch should account for:**

1. **`DegreeFilter` measures ENTITY degree, and a self-loop counts +2 on both
   sides.** So under Option 1 the walk is *actively attracted* to self-loop
   nodes — they read as higher-degree, which `GREATER_OR_EQUAL` climbs toward.
   That makes the "if it reaches a self-loop node it dies" fantasy structural
   rather than lucky. Option 2 has the same pull for the same reason.
2. **The Sum doubling is only 2× — the crit is the real lever.** "Low per-hop
   scaling, but a self-loop node is a guaranteed kill" cannot come from the
   reducer: 2 × (a deliberately tiny number) is still tiny. If the design wants
   a low-floor/lethal-ceiling curve, the crit multiplier (and/or a self-loop-
   specific progression) has to carry it, and then Sum-vs-Max is a much smaller
   balance decision than it looks.

Recommended next step: `/swarmify` **#417** rather than patching the `.tres` — the test and the description both have to move with whatever wins, and
the test additionally reads a `factor` property `ScaledAddProgression` does not
have (see the baseline error), so it needs real work under either branch.

**B2 — RimRing CUSTOM curve → SETTLED 2026-08-14: baked as preset 5 (MESA), aa31522.** The
composite authors `height_preset = 4 (CUSTOM)` + `rim_height_style`, so **every**
node in the game takes the unbatched escape hatch: a private `ShaderMaterial` +
its own 64-texel LUT, with no `is_visible_in_tree()` gate on the rebake. The
"one shared material, N rims collapse to one draw call" design is inert in
production at 500–2500 nodes. Bake the curve as a 5th preset in the shader, or
drop both overrides? *(skill-node #1)*

**B3 — RimBonuses: cut it?** Its `_draw_stake_fill` re-implements the stake dial
#341 folded into `rim_ring.gdshader`, including the spinning start angle the
reclaim deliberately removed — two live implementations with *opposite*
documented verdicts, and the preview panel shows the losing one. The auditor's
per-encoder verdict: KEEP InnerDisk / RimRing / SensedOutline / CoreHalos /
CoreSigilBloom, **CUT RimBonuses and RuneRing-as-an-encoder**. Cutting RuneRing
needs a replacement positive control in `test_node_visuals_contract.gd:88` first
— it is the only animating component the shared-clock test can drive.
*(skill-node #10, #11)*

**B4 — Staking: wire it or label it?** `can_stake`/`stake`/`can_extract`/
`extract` (~90 lines, #337's economy) have no production caller — no UI, no
input channel, no AI. Their downstream consumers *are* live (`allocate`'s refill
branch, the cascade's `maxi(fill, 1)` wound multiplier), so balance is shaped by
a cap nothing can raise. Wire a tray verb (#338's shape), or comment the block
as pre-wired-for-#337? *(systems #7)*

**B5 — Does the addon pass get built or deleted?** `AddonPolicy.weight_profiles`
and `AddonPoolEntry.cost` are exported, warned about in
`_get_configuration_warnings`, authored as 3/4/5 in `first_level.tres` — and
**never read**. Two docstrings describe a budget-and-profiles pipeline that was
never implemented; `first_level.tres` even carries
`weight_profiles = Array[Resource]([null])`. Implement it, or delete both knobs
and the fictional docstrings? *(procgen #4)*

**B6 — `first_level.tres` drifted from the v4 seed table.** `base_min/max` is
1/3 vs the doc's 2/4 ("floor of 2 = no budget-1 dead nodes");
`RandomBudgetBoost.count` is 5 vs 10; the INT debuff is `-2/max_tier 3` vs
`-5/max_tier 1`. Separately, `budget_field.outer_radius = 2500` is hardcoded
against an auto-scaling mask, so the documented "range 2..16, mean ~10" envelope
holds at exactly one node count. Re-derive the doc from the shipped values, or
restore the values? This is the envelope #268's balance harness calibrates
against. *(procgen #17, #7)*

**B7 — `CoreAura`/`HealAura`: absorb into `RadiatingEffect`?** There are three
parallel aura mechanisms: `AuraEffect` and `TagAuraEffect` are ~70 lines of
verbatim duplication, and `CoreAura`/`HealAura` is a third path with its own
hardcoded hop-linear falloff and its own BFS, dispatched from
`Entity._on_turn_started` rather than the effect hooks. The `reach × metric ×
distance_scale` vocabulary was built for exactly this. Absorb, or keep the core
aura special? *(vfx #2 — the auditor calls `effects/` the best-designed thing in
that slice)*

**B9 — What should `crest_r` actually be?** Nothing has ever rendered a rim
at anything but `0.0` — below `inner_radius`, so the bevel spans the whole band
with no flat floor, which is outside crest_r's own documented range
(`inner_radius < crest_r <= outer_radius`). Two authored values disagree with
that and with each other, and **both were inert**: `rim_ring.gd`'s script
default (28.0, midway of 24/32) and `skill_node_lab.tscn`'s 40.0 (midway of
36/44). So somebody twice authored "crest midway" and twice never saw it. The
forward is now wired (A3.7), which makes this a one-number change with a
board-wide effect: keep the shipped 0.0 (and fix the docstring + the two
authored values that lie), or adopt midway and re-check legibility at
500–2500 nodes? **Not headless-verifiable** — same class as A1.1, and the
`Xvfb :99` + `--rendering-driver opengl3` recipe in the A1.1 note is the way to
get a real frame. *(skill-node #6, escalated from A3.7)*

**B8 — Export preset ships every dev tool.** `export_filter="all_resources"`
with an empty `exclude_filter` packs all nine sandbox panels, GUT, `tools/`,
`test/` and `docs/` into the release build. Nothing is *reachable* from `Boot`,
but the balance harness, the env-writing bloom panel and GUT all ship one
`load()` away. Set `exclude_filter="addons/*,tools/*,test/*,docs/*"`? *(devtools
#13 — flagged as an ask only because it changes what ships)*

---

## C — File as issues (structural)

One hub, children via `gh issue create --parent`. Ranked by the auditors'
severity.

| # | Title | Why it's issue-shaped | Source |
|---|---|---|---|
| C1 | Bring self-loops into the edge batch; retire the second render path | #413 moved regular edges to the multimesh and left self-loops on `_draw` + z-index + `modulate`. Two colour functions, two vision models, two z models. A1.1/A1.2 are symptom patches; this is the cause. Afterwards `Edges` can stop being a CanvasItem. | graph-core #4 |
| C2 | Split `graph_procgen.gd`'s six phases into typed objects | 1066-line static class; `generate` is one 190-line function threading 8 loose locals. Tests *and* the playground reach through underscore-privates because there is no contract. Unblocks C3, C4, procgen #13/#14. | procgen #1 |
| C3 | Promote `StatModifierAggregator` out of stub state | Self-flagged TODO owns the v4 content hot path; `extends Resource` for a pure accumulator; O(n) linear scan inside a Dictionary keyed by the thing it scans for; `assert(false, "Can't merge SET yet")` reachable from ordinary `.tres` authoring. | procgen #2 |
| C4 | `already_rolled` is a dead channel in v4 | `ctx.already_rolled = out` where `out` is never appended to post-rewrite. Every `WeightProfile` reading it sees nothing, and unit tests pass because they set it by hand. Feed it or delete it. | procgen #3 |
| C5 | `generate` mutates the config it is handed | `shape_mask.size_for()` overwrites the authored radius; `_propagate_mask_radius` writes into sub-resources — against procgen.md's stated purity, and with `@tool` + Godot's path-cached resources it can write generated values back to the on-disk preset. Wants a `ResolvedConfig`. | procgen #5 |
| C6 | Extract `LocalScaleMutator` / `NodeFeedback` / `NodeCombatHealth` from `SkillNode` | 1608 lines, five concerns, three clean seams that come out without touching anything else. 34 commits in three weeks all land in this file. | skill-node #4 |
| C7 | `self_loops` is derived state that the editor serializes | `@export var self_loops: Array[Edge]` written by three parties on a `@tool` class. The owner's WIP already baked `[null, NodePath(…)]`, making `self_loop_count` read 2 for one loop → `GraphMirror.get_degree` over-reports by +2 while `Graph._ensure_topology` counts correctly. **Two disagreeing degree answers feeding spell `min_degree` gating.** | skill-node #5, graph-core #5 |
| C8 | Melee blade construction is written three times | `MeleeAttackPlan.build_blade_state` ≈ `SkillBlade.build_from_skill_nodes`; `build_drivers` is a verbatim copy of `_build_swing_drivers`; `MeleePreview.launch` re-runs the pipeline a third time. **Already drifted once in a shipped fix** (`e23d975`, addon loop added to one copy). | attack #1 |
| C9 | Comment on #381: the hit-list shape | `AttackOutcome.hits`/`heals` + `PropagationEvent.damage`/`heal` are parallel per-kind slots; `spell_resolver.gd:96` ships a live `assert` guarding the limitation. #381 exists and is the right shape — add the settle-point about where `DamageInstance.Type` lives, since `HealingInstance` has no `type`. | attack #2 |
| C10 | Move the cascade out of `BattleSystem` | `_on_node_depleted` + `_cascade_layers` (78 lines) never reads `attack_plan`, reacts to a global bus signal, and does defender-side ownership accounting that is AllocationSystem's subject. The "wound + chip accompanies every forced dealloc" invariant is unreachable from any other forced-dealloc caller — `deallocate_all_owned` already bypasses it. | systems #3 |
| C11 | One teardown atom in `AllocationSystem` | `deallocate` / `force_deallocate` each re-implement the same five-step teardown; `register_scene_authored_ownership` is a third setup path re-listing side effects. #376's `clear_scaled_effect_sets` already needed the double-edit; A3.1 is that failure on the setup side. | systems #2 |
| C12 | Unify the test fixture layer | 186 of 189 scripts `extends GutTest` bare; 44 rebuild the world identically down to the string literals; 37 also hand-build `AllocationSystem.new()`. Promote `spell_test_helper.gd` + `balance_fixture.gd` into `test/unit/_fixtures/`. Prefer a `RefCounted` fixture over a base class — GUT collects on the `test_` filename prefix, so helper files already coexist uncollected. | test-infra #1, #4, #8 |
| C13 | Gate the suite | No `.github/`, no hook — `mise run test` is invoked only by prose in skill files, and `drone/SKILL.md` explicitly permits handing a red suite onward. Add CI or a `pre-push` running `check && test`. | test-infra #2 |
| C14 | Board↔Stat reference cycle leaks every duplicated board | `StatBoard` holds `Stat`s by `@export`; `Stat._board` holds the board back by strong ref and mirrors it onto `Stat.bins.board`. 77 test files `duplicate(true)` a board, mostly per-`before_each`. Leaked live `Stat`s stay connected to `value_changed` and `Events` — an order-dependence hazard, not just memory. **Falls in the unaudited stats slice (D1).** | test-infra #3 |
| C15 | Finish the `FusedPanel` migration (#345) | Every HUD scene still instantiates `GlassPanel`, which `duplicate()`s a material per instance and has no HDR path; `FusedPanel`'s uniform set is a strict superset. The HUD can never bloom its borders while the tooltip fan does. | vfx #1, #7 |
| C16 | Type `EffectInstance`'s grant rows | The three-way `Effect`/`EffectInstance`/`EffectContext` split is right in principle, wrong at the seam: `_grants` is `Array[Dictionary]` with a `&"kind"` string, and the same hand-rolled switch appears in both `revoke()` and `revoke_all()`. A `Grant` base with `apply`/`revert` makes both one line. **This is the verdict on the `effect_context.gd:12` TODO.** | vfx #4 |
| C17 | Migrate the nine legacy `panel_scene` tabs | Not six — `10_spell`, `15_node_visuals`, `17_gimbal_3d`, `20_vfx`, `30_statboard`, `35_procgen`, `40_allocation`, `50_loot`, `60_toast`. Each is a 3-line `.tscn` edit against the `70_bloom_tab.tscn` template; then delete the `panel_scene` export and ~45 lines of dual-mode mount/reload. Pairs with A5.6/A5.7 so the migration gains pressure. | devtools #3, #4, #5 |
| C18 | Fix the spell playground's half-authored/half-generated graph | Nodes and entities are authored; every edge is generated at `_ready` and every position is overwritten by `_layout_world`. The panel's own TODO ("THIS IS SUPPOSED TO BE A PRE-AUTHORED SCENE") is unimplementable while A1.3's guard exists. | devtools #2 |
| C19 | Aura overlay + fog: coalesce and finish #413 | `_refresh` walks every SkillNode per allocation signal and re-uploads three data textures — a K-node cascade pays K full O(N) rebuilds. And `_apply_per_element_dimming` still CPU-dims every node per frame while edges moved to per-fragment self-shading. | vfx #11, #12 |
| C20 | Per-repaint quadratic walks in the melee and ranged plans | `_is_neighbor_of_blade_set` walks all edges per node per repaint; `get_node_role`/`get_node_range` re-run a navigator leaf query per node. #385 fixed exactly this for `MagicAttackPlan` and did not generalise. | attack #7, #8 |
| C21 | Collapse the six reducer files into one `FoldReducer` | Each is `_merge_payload_defaults` + one fold. **Counter-note for the issue body: do NOT collapse the four `HopDamageProgression` subclasses** — `flat_add_progression.gd:8-22` is an explicit trap marker recording that the class was deleted once as a "dimensional bug" and deliberately restored per the D-32 amendment. | attack #4 |
| C22 | `AllocationVFX`: five code-composed effect trees → scenes | ~25 property assignments each plus 20 tuning constants in a 430-line file; none previewable or tunable, which is *why* all five were missed by the HDR migration. The shatter also builds ~48 chained tweeners per node. | vfx #15, #18 |
| C23 | `TurnManager` has no death awareness | `GameRoot._on_entity_died` writes `current_entity = null` directly, past `end_turn()`, so `turn_ended` never fires when the acting entity dies on its own turn. The only guard on the invariant is an `assert` compiled out in release. | systems #12 |
| C24 | Coverage backlog (file against #284/#357/#358/#359) | No test names `hop_range_finder`, `euclidean_range_finder`, `range_visual`, `node_targeting`, **`graph_mirror.gd`** (the `get_degree` authority the degree rule routes everyone to), `astar_skill_tree.gd`, or four propagation filters. **`graph_mirror.gd` now has
`test/unit/test_graph_mirror.gd`** (landed with A4.1/A4.2) — strike it from the
list; the rest stand. | test-infra #7, #14 |

**Lower-priority C candidates** (real, but schedule after the above): `HealthBar`/
`CoreHealthBar` are the same class twice (skill-node #13) · `_sync_visuals`
triggers ~25 redundant shader resyncs and `_refresh_radius` fires it twice
(skill-node #9, #17) · Keystone is a parallel authoring surface, #336 (skill-node
#15) · denial feedback paints the *player's* islanding for anyone's denial
(systems #5) · drag-badge presentation composed in the input router (systems #11)
· `ArmedMode` subclasses reach into controller privates (systems #13) · armed
plan becomes unpoppable when the AP gate closes (systems #14) · killer
attribution is structurally unenforced (systems #8) · `CastSpell`/
`PropagationContext` duplicate four fields (attack #6) · nine hand-written
weighted-pick loops with three different tail behaviours (procgen #18) ·
`BalanceFixture` is a third system-wiring source, already diverged (devtools #7)
· balance harness calls `Entity`'s private signal handlers (devtools #8) · every
sandbox tab is built at editor start, three SubViewports render forever
(devtools #9) · no shared world-content fixture for the sandboxes (devtools #11,
#12) · `MagicBounceCoordinator`'s dead `Beat` class and 8-export verb ladder
(vfx #5, #6) · `SceneLoader` autoloaded with zero callers, #212 (graph-core #11)
· `EntityNavigator` code-composed instead of scene-packaged (graph-core #8) ·
overlapping endpoints leave a stale multimesh transform (graph-core #9) ·
`archetype_stamp.seed_node_index` indexes a list that only exists after
generation (procgen #11) · procgen's connectivity certificate is a
release-stripped `assert` (procgen #15) · pool `_get_configuration_warnings` are
unreachable through normal authoring, #349 (procgen #21) · 43 wall-clock sleeps
and 470 private-state reaches in the suite (test-infra #9, #10).

---

## D — Still open

**D1 — Three slices were never audited.** Budget died before they ran; the
prompts are reconstructable from `00-brief.md`.
1. `stats_system/` + `skill_node/addons/` — **owns C14**, the board↔stat cycle.
2. `ui/tooltip_fan/` + `ui/spell_tooltip/`
3. `ui/hud/` + `ui/gauges/` — carries an unfulfilled owner ask: an explicit
   inventory of which HUD elements use real emissive vs. faked pre-bloom glow,
   with `pool_gauge` / `composite_bar_gauge` / `capacity_pip` named directly.
   The vfx report's §A table is the model to copy; note it already scores the
   HUD's panels as fake via `GlassPanel` (C15).

**D2 — Owner WIP in the working tree.** `scenes/dev_sandbox.tscn`,
`addons/spell_playground/playground_panel.tscn`, `attack/spell/defs/bruiser.tres`
(also gained an unused `rank_pass.gd` ext_resource), `reverberator.tres`. Left
dirty deliberately as the reproduction case. **Ask before touching** — A1.3 and
B1 both land in these files.

**D3 — Verification debt.** A1.1 cannot be closed headless. Nothing in A or C
has been visually verified on a real opengl3 renderer.
