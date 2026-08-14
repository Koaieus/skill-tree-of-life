# Audit — `skill_node/` (skill_node.gd, visuals/, addons/, composing scenes)

Read in full: all 33 `.gd` under `skill_node/`, plus `skill_node.tscn`,
`node_visuals_composite.tscn`, `inner_disk.tscn`, `rim_ring.tscn`, the five
addon `.tscn`, `rim_ring_curve.tres`, the two matrix scenes, the panel + lab
scenes, `test/unit/test_node_visuals_contract.gd`, and (as dependencies)
`graph/edge.gd`, `graph/graph.gd`, `graph/graph_mirror.gd`,
`stats_system/stat_modifier.gd`. Read-only: no edits, no test runs, no game runs.

---

### 1. LARGE | skill_node/visuals/node_visuals_composite.tscn:35 | Every node takes RimRing's unbatched escape hatch
**Defect:** The composite's RimRing is authored `height_preset = 4` (CUSTOM) with `rim_height_style = rim_ring_curve.tres`, so `rim_ring.gd:242 _use_custom_curve` is true for **every** SkillNode in the game, sending each one down `_rebake_lut()` → a private `ShaderMaterial.new()` (`resource_local_to_scene = true`) plus its own 64-texel `ImageTexture`.
**Breaks:** The "ONE shared static material + instance uniforms so N rims collapse to one draw call" design (`.claude/rules/rendering-performance.md`, rim_ring's class doc) is inert in production — at 500–2500 nodes that is one material, one LUT bake and one draw call per rim, and unlike `_sync_material` the `_rebake_lut()` path has **no** `is_visible_in_tree()` gate, so fogged nodes pay the allocation too; the documented "deliberate, opt-in cost for the escape hatch" is in fact the default path, tested nowhere. (This, not the `set_shader_parameter` calls at `rim_ring.gd:198` / `inner_disk.gd:294,300`, is the real batching break — those three are correct one-time sets on the *shared* material.)
**Fix:** Decide whether that curve is a real design pick — if yes, add it as a 5th baked preset in `rim_ring.gdshader` and set `height_preset` back to a preset index; if no, drop both overrides from the composite scene.

### 2. LARGE | skill_node/visuals/node_visuals_composite.tscn:19-36 | Committed baked instance uniforms defeat the fog gate
**Defect:** The composite bakes 11 `instance_shader_parameters/*` on InnerDisk and 2 on RimRing, `rim_ring.tscn:6-12` bakes 7 more, and `node_visuals_panel.tscn:91-96` another 6 — so a freshly instantiated composite carries instance-uniform state from **load**, before and regardless of `_sync_material()`'s `is_visible_in_tree()` gate.
**Breaks:** This is the #172 regression `.claude/rules/skill-node-visuals.md` names verbatim ("drop them, don't re-save") — every node, fogged or sensed or on the invisible procgen preview graph, claims slots in the shared global instance-uniform buffer whose software-rasterizer ceiling is 4096 items; `SkillNodeVisual._validate_property` blocks *re-baking* but cannot un-apply lines already committed.
**Fix:** Delete every `instance_shader_parameters/*` line from those three scenes, and extend `test_disk_and_rim_ship_no_baked_material` to assert on instance params — it checks only `material` today, which is exactly why this shipped.

### 3. LARGE | test/unit/test_node_visuals_contract.gd:143 | The two failing tests are right; the scenes are wrong
**Defect:** Both failures are the `assert_null(...get_instance_shader_parameter(...))` lines, caused by finding 2: the composite bakes `instance_shader_parameters/tint_color`, scene instantiation applies stored properties by name via `set()` (which `_validate_property`'s STORAGE clearing does not intercept), so a never-visible disk returns non-null — and "expected uniform to be NULL" is GUT's `assert_null` message. The `assert_null(disk.material)` halves still pass, which is why only the uniform assertions go red. Determined by reading the scenes and the engine's load path, not by executing the suite.
**Breaks:** Nothing about the tests is stale — they encode the live #172 invariant, so "fixing the test" would delete the only guard on the instance-uniform budget.
**Fix:** Fix the scenes (finding 2); leave both tests untouched.

### 4. LARGE | skill_node/skill_node.gd:1-1609 | God object: five concerns, three with clean seams
**Defect:** 1608 lines carrying (a) graph/geometry identity, (b) entity+node modifier plumbing, (c) combat HP and regen, (d) the #376 local-scale mutator, (e) hit-flash and denial-feedback tweening — of which (d) and (e) have zero dependence on this class being an `Area2D` with a position and children.
**Breaks:** 34 commits in three weeks all land in one file, so concurrent work on visuals, stats and combat collides in one diff, and the mutator's four private ledgers (`_scaled_sets`, `_scaled_effect_sets`, `_last_allocation_level`, `_local_modifiers`) are reachable from every unrelated method.
**Fix:** Cut three composed objects out: `LocalScaleMutator` (RefCounted owning lines 1146–1350 plus those ledgers, handed the carrier's modifier/effect lists and its two boards), `NodeFeedback` (lines 1496–1586 plus `_hit_flash_tween`/`_feedback_tweens`/`_DENY_*` — pure presentation that already writes only `NodeVisualsComposite.feedback_tint` and two `position`s), and `NodeCombatHealth` (lines 923–1075: `refill`/`apply_turn_regen`/`take_damage`/`heal_damage` plus the `node_health` binding), leaving SkillNode as identity + topology + the addon ledger.

### 5. LARGE | skill_node/skill_node.gd:137 | `self_loops` is a derived index that is `@export`ed
**Defect:** `@export var self_loops: Array[Edge]` is written by three parties on a `@tool` class — `Edge._register_self_loop()` appends from the `from`/`to` setters (`graph/edge.gd:376`, itself `@tool`, so it runs on editor scene load), `Graph.remove_edge` erases (`graph/graph.gd:315`), and scene authors write NodePaths — so the editor serializes whatever the runtime appended.
**Breaks:** This is `.claude/rules/gdscript-pitfalls.md`'s "never write a DERIVED value back into an `@export`" on a class that rule names; the owner's own in-progress edit already shows the trap producing garbage — `addons/spell_playground/playground_panel.tscn:978` (uncommitted WIP, per the brief's Phase 0 baseline) reads `self_loops = [null, NodePath("../../Edges/Edge2")]`, and that null slot makes `self_loop_count` report 2, which `graph_mirror.gd:119` turns into `+4` degree on a node with one loop — corrupting the cut-vertex/islanding queries that gate deallocation. Worth passing to whoever audits `graph/`: an inflated `self_loop_count` on a freshly-authored playground self-loop is a candidate contributor to owner-reported smell #3.
**Fix:** Make `self_loops` a non-exported derived var rebuilt from `Graph`'s edge list — or at minimum guard `_register_self_loop` with `not Engine.is_editor_hint()` and filter nulls in the getter — so authoring a self-loop means authoring an `Edge`, not two half-synced places.

### 6. MEDIUM | skill_node/visuals/node_visuals_composite.gd:303 | `geom_crest_r` is stored and never forwarded
**Defect:** `SkillNode._sync_visuals` (`skill_node.gd:467`) pushes `geom_crest_r = radius - RIM_CREST_INSET` into the composite, whose setter calls `_sync_stake()` — and `_sync_stake()` writes `inner_radius`, `outer_radius`, `tint_mix`, `fill_max` and `fill_current` to RimRing but never `crest_r`.
**Breaks:** The interior bevel control point is never driven: every in-game rim runs at the scene-authored `rim_ring.tscn:14 crest_r = 0.0`, outside the documented `inner_radius < crest_r <= outer_radius` range, so the rim still renders but at a profile nobody chose — and the eyeball-check artifacts (`rim_fill_dial_matrix.tscn`, `rim_archetype_legibility_matrix.tscn`) all author `crest_r = 28.0`, meaning the #341 legibility sweep was judged against a rim the game does not render. `skill_node_lab.tscn:57` authors `geom_crest_r = 40.0`, so someone already tried the knob and got nothing.
**Fix:** Add `_rim_ring.crest_r = geom_crest_r` to `_sync_stake()` and reset `rim_ring.tscn`'s authored `crest_r` to a value inside its own documented range.

### 7. MEDIUM | skill_node/addons/spike_ring_addon.tscn:16 | Second modifier misses `resource_local_to_scene`
**Defect:** `Resource_u38nb` (blade_damage, ADD_BASE 3.0) is authored without `resource_local_to_scene = true`, unlike its sibling `Resource_arix0` and every modifier in every other addon scene.
**Breaks:** `SkillNode._attach_addon` routes `a.get_local_modifiers()` straight through with no clone *because* #377 established that flag as the invariant — so every SpikeRingAddon in the level shares this one instance, and the #376 mutator's live `m.value` write means staking one spiked node silently rewrites the spike damage of every spiked node on the board.
**Fix:** Add the flag to that sub-resource, and add a test walking every `skill_node/addons/*.tscn` asserting it on every `StatModifier` sub-resource.

### 8. MEDIUM | skill_node/skill_node.gd:864 | `get_spike_power` sums across incompatible operations
**Defect:** It adds `mod.get_effective_value(node_board)` for every `blade_damage` modifier on every SpikeRingAddon regardless of `operation`, and `spike_ring_addon.tscn` carries one MULTIPLY (1.5) and one ADD_BASE (3.0).
**Breaks:** `BladePopResolver` reads 4.5 as the defensive spike magnitude while the node's actual `blade_damage` contribution is `(base + 3) × 1.5` — a permanently-wrong number no test can catch, because the correct answer was never written down anywhere.
**Fix:** Derive it from the resolved `get_local_value(&"blade_damage")` against the owner's baseline, or restrict the sum to ADD_BASE/ADD_BONUS and document why the multiplier is excluded.

### 9. MEDIUM | skill_node/skill_node.gd:452 | One `_sync_visuals` triggers ~25 redundant shader resyncs
**Defect:** `_sync_visuals` writes five composite properties whose setters each call `_sync_stake()` (none of the composite's `geom_*` / `stake_level` / `allocation_level` setters has an equality guard), and each `_sync_stake()` writes five RimRing properties whose setters each call `_sync_material()`.
**Breaks:** A *visible* node pays roughly 175 redundant `set_instance_shader_parameter` calls plus 25 `queue_redraw()`s per sync; a fog-hidden node still pays 25 function calls and 25 `is_visible_in_tree()` ancestor walks, since the gate sits inside `_sync_material` rather than before it. `_sync_visuals` runs on `_ready`, on `radius_changed`, on `owner_changed` and on every `allocation_level` write, at 500–2500 nodes (`.claude/rules/skill-node-scale.md`).
**Fix:** Add `if x == value: return` guards to the composite's five setters and coalesce `_sync_stake`/`_sync_shared` behind a `call_deferred` dirty flag.

### 10. MEDIUM | skill_node/visuals/node_visuals_composite.gd:20 | #238's six encoders: four KEEP, two CUT
**Defect:** The brief asks for a per-encoder verdict; read as code, only two of the six are redundant with anything.
**Breaks:** The shelf is reachable — `node_visuals_panel.tscn` instances both shelved scenes — so a designer previewing "the dial" sees the *rejected* implementation (finding 11), and `rune_ring.tscn` is load-bearing in a test while being dead as an encoder.
**Fix:** **KEEP** InnerDisk (the dome + carve, the only shader that draws the body), **KEEP** RimRing (the band, and since #341 the stake dial too), **KEEP** SensedOutline (the only archetype-only draw; its structural info-gate has no substitute), **KEEP** CoreHalos + CoreSigilBloom (core-gated, and they occupy two different registers — a physically-gliding gimbal and a non-gliding bloom, per the #128 travel contract). **CUT** RimBonuses (findings 11 and 12). **CUT** RuneRing as an encoder, but replace `test_node_visuals_contract.gd:88`'s positive control first — it is currently the only animating component the shared-clock test can drive.

### 11. MEDIUM | skill_node/visuals/rim_bonuses.gd:150 | RimBonuses' dial duplicates RimRing's shader dial
**Defect:** `_draw_stake_fill` implements exactly the `fill_current`/`fill_max` semantics #341 folded into `rim_ring.gdshader` (`rim_ring.gd:112-125`), including the spinning start angle that `skill-node-visuals.md` records as the artifact the reclaim deliberately removed; `_tone_color()`'s unallocated-grey likewise duplicates the composite's `FILLED_TINT_MIX` / `UNFILLED_TINT_MIX` swing.
**Breaks:** Two live implementations of one mechanic with *opposite* documented verdicts (spin vs. no spin, contiguous fill vs. 12-o'clock-symmetric), and the losing one is what the preview panel shows.
**Fix:** Delete `rim_bonuses.gd` / `rim_bonuses.tscn` and drop the instance from `node_visuals_panel.tscn`.

### 12. MEDIUM | skill_node/visuals/rim_bonuses.gd:169 | Four independent CPU fake-glow implementations
**Defect:** `rim_bonuses._draw_glow_arc` (3 stacked arcs), `rune_ring._draw_band`'s `edge_glow`, `core_halos._append_glow_strip` + `_glow_colors`, and `core_sigil_bloom._draw`'s `glow_layers` loop each fake bloom with stacked translucent strokes; `rim_bonuses.gd:170` still asserts "no project-wide glow/bloom environment exists yet to justify one".
**Breaks:** That comment is now false — `.claude/rules/hdr-color.md` documents a real per-viewport bloom pass and says a glow is authored only via `Emissive.at()` or a `Tier*` variation. The only `Emissive.` call site in this entire slice is `skill_dust_addon.gd:66`. (`rim_ring.gdshader:248` is *not* one of the offenders — its comment says it is `Emissive.at(ring_tint, stops)` hand-rolled in GLSL, which is compliant in substance.)
**Fix:** Route the four through `Emissive.at()` tiers — CoreSigilBloom and CoreHalos are core-gated, so the cost is one node per entity — and delete the stale comment.

### 13. MEDIUM | skill_node/health_bar.gd:1 | HealthBar and CoreHealthBar are the same class twice
**Defect:** `health_bar.gd` (164 lines) and `core_health_bar.gd` (117) share `_bind_pool`/`bind_health`, `_on_current_changed`, `_on_max_changed`, `_sync`, `_fade_to`, `_tween_value`, `_on_value_changed` and all six duration constants verbatim; they differ only in three fill colours, where the pool comes from, and whether visibility is hover-gated.
**Breaks:** The #147 `_fade_target` fix had to be written twice — both files carry the comment — so the next fade or tween bug needs fixing in two places and one will be missed.
**Fix:** Extract a `PoolBar` base (`ProgressBar` + `bind_pool()` + fade/tween/colour-ratio) with the three colours as exports and an overridable `_wants_visible()`; both scripts drop to roughly 25 lines.

### 14. MEDIUM | skill_node/skill_node.gd:474 | Emblem pipeline re-resolves on every owner change
**Defect:** `_sync_visuals` ends with `EmblemResolver.resolve(get_emblem_contributions()).carve`; `get_emblem_contributions` calls `get_node_effects()` (which `duplicate()`s `effects` and `append_array`s per keystone and addon), mints a fresh `EmblemSpec` per contribution, and the resolver allocates a `Resolution` plus two Arrays — all re-run on `owner_changed`, which cannot change the carve.
**Breaks:** Roughly eight heap allocations per node per sync at 500–2500 nodes (`.claude/rules/skill-node-scale.md`), for a result depending only on `archetype`, `keystone`, effects and addons.
**Fix:** Resolve the carve behind its own invalidation (archetype/keystone/effect/addon change) instead of inside the geometry-and-tint sync.

### 15. MEDIUM | skill_node/skill_node.gd:44 | TODO(#336): Keystone is a parallel authoring surface
**Defect:** `Keystone` is a `Resource` mirroring a subset of SkillNode's own authoring surface (modifiers, carve_shape, effects, display_name) and stamping itself on; three separate methods special-case it (`get_node_effects:780`, `get_display_name:794`, `get_emblem_contributions:912`).
**Breaks:** Two ways to say "this node carries content" — an inherited `.tscn` with baked modifiers/addons versus a Resource that copies them in — which is the parallel-mechanism smell the TODO itself names; every new node-content feature has to be implemented on both.
**Fix:** Land #336: make a Keystone an inherited `skill_node.tscn` and delete the Resource plus its three special cases.

### 16. MEDIUM | skill_node/visuals/node_visuals_composite.gd:139 | `_children` is the hand-written fan-out the docs forbid
**Defect:** The identity contract's stated advantage over a hand-written fan-out is that `_sync_shared()` loops — but it loops an `@onready` array literal naming five children by unique name, which *is* the hand-maintained list.
**Breaks:** Adding a `SkillNodeVisual` to `node_visuals_composite.tscn` and forgetting this line reproduces the exact RimBonuses bug the class doc describes (renders its default tint forever, fails nothing loudly); only `test_composite_pushes_identity_to_every_child` would catch it, and only because that test uses `find_children` instead.
**Fix:** Build `_children` with `find_children("*", "", true, false)` filtered on `is SkillNodeVisual` — the same predicate the test already uses.

### 17. MEDIUM | skill_node/skill_node.gd:1372 | `_refresh_radius` syncs visuals twice per call
**Defect:** It emits `radius_changed` — which `_ready:357` connected directly to `_sync_visuals` — and then calls `_sync_visuals()` itself four lines later.
**Breaks:** Doubles finding 9's cost on every `base_radius` / `stake_level` / `stake_radius_delta` write, and makes the connection at line 357 look load-bearing when it is the only one that should exist.
**Fix:** Keep the signal or keep the call, not both.

### 18. NIT | skill_node/visuals/sensed_outline.gd:22 | Hand-picked glow/tint floats with no tier
**Defect:** Beyond the four fake glows in finding 12, the family carries bare tuned constants where `.claude/rules/hdr-color.md` wants a named tier: `SensedOutline.OUTLINE_ALPHA = 0.30`, `rim_ring._effective_tint`'s `s * 1.35` / `v * 1.15` saturate-and-brighten, `core_halos.GIMBAL_GLOW_WIDTH = 3.0` and the `c.a * 0.4` in `_glow_colors`, and `core_sigil_bloom`'s `0.22` / `0.85` / `0.95` alphas.
**Breaks:** Each is a private guess at "how bright is bright" that will read wrong once the shared bloom pass is retuned, and none is discoverable from the tier vocabulary the rest of the project now uses.
**Fix:** Express each as an `Emissive` tier or a documented style export as the surrounding component is touched; they are individually harmless and collectively a second, invisible brightness system.

### 19. NIT | skill_node/addons/spike_ring_addon.gd:19 | Getter-only `@export` that the scene assigns
**Defect:** `spike_color` is declared `@export var` with only a `get()`, and `spike_ring_addon.tscn:26` writes `spike_color = Color(1, 1, 1, 1)` to it.
**Breaks:** The authored value is discarded on load and the inspector shows an editable field that cannot be edited, so the next person tuning spike colour changes the scene and sees nothing happen.
**Fix:** Drop `@export` (keep the getter) and remove the line from the scene.

### 20. NIT | skill_node/skill_node.gd:1409 | `can_attach_addon` allocates to read a size
**Defect:** `get_addons().size()` duplicates the whole ledger just to count it, on a method the #406 temp-upgrade UI calls per candidate node.
**Breaks:** A pointless per-node allocation on a path whose own doc justifies reading the ledger precisely because it runs at graph scale.
**Fix:** `_addons.size()` — the loop two lines below already iterates `_addons` directly.

### 21. NIT | skill_node/visuals/core_halos_back.gd:26 | Back layer reaches into three private members
**Defect:** It reads `_halos._halo_color`, `_halos._gimbal_runs(...)` and `_halos._draw_batch(...)` — all underscore-private on the parent — through an untyped `get_parent()`.
**Breaks:** The duck-typed coupling is deliberate and documented, but `is_gimbal_active()` is the only member of the shared contract that is actually public, so renaming any of the other three breaks a second file with no compile error.
**Fix:** Promote the three to public names (`halo_color`, `gimbal_runs`, `draw_batch`) so the real contract is visible from both sides.

### 22. NIT | skill_node/visuals/core_halos.gd:191 | Gimbal geometry passes untyped string-keyed Dictionaries
**Defect:** `_gimbal_runs` returns a `Dictionary` keyed `"front"`/`"back"`, `_build_run` a four-key Dictionary of parallel arrays, `_gimbal_batch` a `{"points","colors","indices"}` — all bare, all string-keyed, two of them consumed from another file.
**Breaks:** A typo in any of the eight keys is a runtime nil rather than a parse error, across a file boundary.
**Fix:** Two inner `RefCounted` structs (`Run` with the four packed arrays, `Batch` with the three); the call sites total about five lines.

### 23. NIT | skill_node/visuals/inner_disk.gd:413-521 | 110 lines of CPU gem geometry inside the renderer
**Defect:** `_build_gem_lut` / `_gem_centroid` / `_gem_edge_normal` / `_gem_nearest_edge` / `_gem_height_grad` / `_gem_inside` / `_gem_coverage` plus 15 `GEM_*` constants form a self-contained convex-polygon SDF bake inside the disk renderer, while the shape they bake belongs to `GemCarveShape` — whose own doc says to "tune the shape itself in InnerDisk's GEM_* bake constants".
**Breaks:** A shape's parameters live in a different file from the shape, so `GemCarveShape` reads as an empty marker class and a fifth of `inner_disk.gd` is one relic's geometry.
**Fix:** Move the bake and its constants onto `GemCarveShape` as a `static func bake_lut()`; InnerDisk keeps only the bind-to-shared-material line.

### 24. NIT | skill_node/visuals/node_visuals_composite.gd:215 | `_apply_sensed` re-resolves two children on every vision tick
**Defect:** Two `get_node_or_null` lookups run on every `sensed` write, and the composite's `sensed` setter has no equality guard while `SkillNode._apply_sensed_state:421` assigns `_node_visuals.sensed` unconditionally — so VisionSystem's per-recompute `revealed` writes fire it too, even when `sensed` is unchanged.
**Breaks:** Two string-path lookups per node per vision recompute, for the whole life of the node, at graph scale.
**Fix:** Guard the composite's `sensed` setter on equality and cache the two node references after the first in-tree resolve (the pre-tree direct-path lookup is genuinely required and must stay).

### 25. NIT | skill_node/visuals/rim_bonuses.gd:51 | `fill_current` unclamped here, clamped in RimRing
**Defect:** `RimRing.fill_current` clamps to `[0, fill_max]` and `fill_max` re-fires it; `RimBonuses.fill_current` does neither, despite identical names and identical documented semantics.
**Breaks:** The same authored M/N pair renders differently in the sandbox panel than in the game whenever M > N — precisely the comparison the panel exists to support.
**Fix:** Moot once finding 11's CUT lands; otherwise copy RimRing's clamp.

---

## Verdict

The architecture here is unusually well modelled — the identity/lighting split, the contribute→resolve emblem pipeline, the shared-material-plus-instance-uniform discipline and the `_addons` ledger are all genuinely good, and the rule files describing them are accurate. What has decayed is the **boundary between the scripts and the scenes that compose them**: three of the five most serious findings (the CUSTOM curve on every rim, the baked instance uniforms, the dropped `crest_r`) are cases where a `.tscn` silently opts out of, or fails to complete, a contract its script documents at length, and each quietly voids a performance or fidelity property the whole design was built around. Findings 1, 2, 6, 7 and 8 are live bugs and should be triaged first; 4, 5, 10–17 are structural and can be scheduled. `skill_node.gd` is a real god object, but a well-behaved one — three clean seams come out without touching anything else. The two failing tests are correct and should stay red until the scenes are cleaned.
