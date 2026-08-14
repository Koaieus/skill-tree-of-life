# Audit — `procgen/` (47 files, 4208 lines)

Scope read in full: every `.gd` under `procgen/`, plus `first_level.tres`,
`constitution.tres`, `specimen_pool_set.tres`, `docs/domain/procgen.md`,
`docs/domain/procgen-v4.md`, and the consuming tests / `scenes/procgen_play_sandbox.gd`.

---

### 1. LARGE | procgen/graph_procgen.gd:73 | 1066-line static class hides six phases
**Defect:** `generate` is one 190-line static function threading 8 loose locals (`positions`, `edge_pairs`, `type_assignments`, `starters`, `starter_indices`, `placement_ctx`, `nodes`, `rng`) through six phases that never get named as types.
**Breaks:** no phase is independently testable or swappable — the tests reach into `_assign_archetypes` / `_roll_modifiers_v4` / `_weighted_pick_addon` / `_weighted_pick_from` as *private statics*, and so does `playground_panel.gd`, so every consumer is coupled to implementation names rather than a contract; adding phase 7 means editing the same function again.
**Fix:** six objects with typed in/out — `StarterAssembly(config,rng) -> Array[StartingPoint]`, `PositionSampling -> Array[Vector2]`, `Topology(positions,connectivity) -> Array[Vector2i]`, `ArchetypeAssignment(+stamps) -> PackedInt32Array`, `ContentRoll(PlacementContext) -> per-node payload`, `Instantiation(payload, graph) -> result` — with `generate` reduced to wiring them and emitting progress.

### 2. LARGE | procgen/graph_procgen.gd:918 | Self-flagged stub owns the content hot path
**Defect:** `StatModifierAggregator` carries its own `# TODO: review this stub and promote it to something real if needed -- or revert to previous`, `extends Resource` for a pure accumulator, does an O(n) linear `_find_match` scan *inside* a `Dictionary[StatModifier,int]` (the dictionary keying buys nothing), and `_merge` hits `assert(false, "Can't merge SET value yet")` — a stat pool authored with `operation = SET` is legal per `StatPool`'s export and crashes here in debug, silently mis-aggregating in release.
**Breaks:** the per-(stat,op) aggregation the whole v4 draw rests on is provisional code with an unimplemented branch reachable from ordinary `.tres` authoring.
**Fix:** promote to a `RefCounted` in its own file keyed by `"%s|%d" % [stat_id, operation]` (no scan), and implement SET as `max` — which is what `procgen-v4.md` and `stat_pool.gd`'s own docstring already promise.

### 3. LARGE | procgen/graph_procgen.gd:851 | `already_rolled` is permanently empty in v4
**Defect:** `ctx.already_rolled = out`, but `out` is never appended to after the v4 rewrite — rolls go into the aggregator and `out` only survives as the empty early-return value.
**Breaks:** every `WeightProfile` that reads `context.already_rolled` now silently sees nothing. `CollisionProfile` is documented as deliberately dropped, but the channel itself is dead, so the next "don't roll two vision mods" profile will pass its unit test (which sets `already_rolled` by hand — `test_weight_profiles.gd:104`) and do nothing in generation.
**Fix:** either feed the aggregator's running contents into `ctx.already_rolled` each iteration, or delete the field and its docstring so the dead channel can't be mistaken for a live one.

### 4. LARGE | procgen/pools/addon_policy.gd:23 | The addon pass's documented pipeline does not exist
**Defect:** `AddonPolicy.weight_profiles` is exported and never read anywhere; `AddonPoolEntry.cost` is exported, warned about in `_get_configuration_warnings`, authored as 3/4/5 in `first_level.tres` — and never read either. `_roll_and_attach_addons` samples a slot count and does an unweighted-by-profile, uncosted pick.
**Breaks:** `addon_pool.gd`'s docstring ("subtract its cost from the addon budget, repeat", "profiles compose multiplicatively") and `addon_policy.gd`'s ("the addon-pass WeightContext carries the modifier-pass output as `already_rolled`") describe a system that was never built; `first_level.tres` even carries `weight_profiles = Array[Resource]([null])`. A designer tuning addon costs changes nothing and gets no feedback.
**Fix:** delete `cost` + `weight_profiles` + the fictional docstrings (slot-count weighting is the actual model), or implement the budget/profile pass — but not ship both stories.

### 5. LARGE | procgen/graph_procgen.gd:90 | `generate` mutates the config it is handed
**Defect:** `config.shape_mask.size_for(...)` overwrites the mask's authored radius and `_propagate_mask_radius` writes `outer_radius` into the config's field/profile sub-resources, contradicting `docs/domain/procgen.md`'s "no in-memory state — every call is a pure function of `(config, graph, rng_seed)`".
**Breaks:** the `outer_radius <= 0` opt-in sentinel is consumed on first use, so a second `generate` on the same config keeps a radius computed for a different `node_count`; and because Godot caches resources by path, forgetting the `duplicate(true)` every caller currently remembers writes generated values back into the on-disk preset (`@tool` + editor = serialized, per `gdscript-pitfalls.md`'s "never write a DERIVED value back into an `@export`").
**Fix:** resolve mask size and radii into a `ResolvedConfig` value object built at the top of `generate`, leaving the authored `config` untouched.

### 6. MEDIUM | procgen/playground/node_graph_view.gd:288 | `.color` on `ArchetypePolicy` — property doesn't exist
**Defect:** `_draw_stamp_regions` reads `_archetypes[stamp.archetype_idx].color`, but `ArchetypePolicy` has no `color` — the colour moved to `archetype.color` (the read-through the same file does correctly at lines 135 and 149).
**Breaks:** every `_draw` after a stamp is painted throws "Invalid access to property 'color'", so Paint Mode — the headline #166 feature of the tab — errors on the first repaint and the stamp region never draws.
**Fix:** `_archetypes[idx].archetype.color` with a null guard, matching `paint_stamp`.

### 7. MEDIUM | procgen/presets/first_level/first_level.tres | `budget_field.outer_radius` hardcoded against an auto-scaled mask
**Defect:** the budget `RadialGradientField` pins `outer_radius = 2500` while `shape_circle.auto_scale` (default true) resizes the mask per `node_count` — ~3212 at the preset's 800 nodes, ~800 at `procgen_play_sandbox`'s `node_count_override = 50`.
**Breaks:** at 800 nodes the outer ~22% of the map is clamped to max budget; at the shipped sandbox's 50 nodes the whole map sits in the gradient's first 30%, so `procgen-v4.md`'s "range 2..16, mean ~10" envelope holds at exactly one node count and nobody is told.
**Fix:** set `outer_radius = 0` so `_propagate_mask_radius` tracks the mask (the mechanism already exists and `rbp_main` uses it), and express the gradient's inner plateau as a fraction rather than an absolute 200.

### 8. MEDIUM | procgen/graph_procgen.gd:83 | The effective seed is never reported
**Defect:** `rng.seed = config.seed if config.seed != 0 else randi()` — when `seed == 0` the drawn seed is discarded, and the returned dict (`nodes` / `starting_nodes` / `starters`) has no slot for it.
**Breaks:** a level that generates badly cannot be reproduced; "seed 0 reseeds randomly per run, so non-zero seeds are reproducible" (procgen.md) is true and useless, because nothing tells you what the random run's seed was.
**Fix:** hoist the resolved seed into a local, return it as `result["seed"]`, and have `procgen_play_sandbox` log it (it already derives its seeding stream from `cfg.seed` and hits the same blind spot at line ~99).

### 9. MEDIUM | procgen/pools/stat_pool.gd:190 | Debuff `max_tier` rule contradicts the settled decision in three places
**Defect:** `_get_configuration_warnings` flags "debuff pool with `max_tier > 1` — D9 pins debuffs to a single tier", the class docstring says "pin `max_tier = 1`", and `procgen-v4.md` repeats it — but laddered debuffs were settled as intended (see `test_pool_seed_values.gd:99`, "Laddered debuffs are the intended reading (settled 2026-08-07)"), and `constitution.tres`'s shipped INT debuff is `unit_value = -2, max_tier = 3`.
**Breaks:** the repo's only debuff pool trips its own validator on every editor open, training designers to ignore procgen config warnings — the exact channel this dir relies on for tag typos.
**Fix:** delete that warning, update the two docstrings and the v4 doc's Debuffs (D9) section to the laddered model the test now pins.

### 10. MEDIUM | procgen/pools/stat_pool.gd:147 | Sign of `unit_value` carries two unrelated meanings
**Defect:** `unit_value < 0` simultaneously means "the rolled value is negative" *and* "this pool refunds budget" (`e.cost = -t_cost`); `_op_symbol` is sign-blind, so `constitution.tres`'s debuff pool's `resource_name` reads "intelligence +%" in the inspector.
**Breaks:** the inspector labels the repo's only debuff as a buff (the TODO at :147 names this), and the conflation blocks the real case behind it — a stat where *lower* is better would need a positive `unit_value` that still refunds, which the sign encoding cannot express.
**Fix:** derive the symbol from `sign(unit_value)` now (a one-line fix to the lie), and when a lower-is-better stat lands, put the direction on `StatDef` (which today has `display_as_percent` but no polarity flag) and read `is_debuff` from `sign(unit_value) != stat_polarity` rather than from the sign alone.

### 11. MEDIUM | procgen/archetypes/archetype_stamp.gd:32 | `seed_node_index` indexes a list that only exists after generation
**Defect:** TOPOLOGICAL stamps are authored with an index into the Poisson position list, which is re-sampled from the RNG on every run.
**Breaks:** an authored `seed_node_index` designates a different, unpredictable node for every seed, so the mode is unusable in a preset — and `_apply_archetype_stamps` only `push_warning`s on out-of-range, never on "this is meaningless". It is also the only stamp mode the playground cannot simulate (`_draw_stamp_regions` skips non-EUCLIDEAN).
**Fix:** author the seed as a world position (like EUCLIDEAN's `position`) and resolve it to the nearest node index at generate time, exactly as `KeystonePlacement` already does.

### 12. MEDIUM | procgen/graph_procgen.gd:1010 | `ModifierPool` / `_weighted_pick_from` are v3 corpses kept alive by tests
**Defect:** `_weighted_pick_from` (35 lines), `ModifierPool` (42 lines), and `ModifierPoolEntry.is_in_budget` / `has_weight` have **zero** production callers — the only references are `test_weight_profiles.gd` and `test_modifier_pool_entry.gd`.
**Breaks:** the v3→v4 migration left two parallel draw implementations; `_v4_weighted_pick`'s own docstring says it "mirrors `_weighted_pick_from`", so the two will drift and the test suite will keep certifying the dead one.
**Fix:** delete all four, and re-point `test_weight_profiles.gd` at `_v4_weighted_pick` — which is what actually ships.

### 13. MEDIUM | procgen/graph_procgen.gd:668 | Two BFS-within-hops implementations, three adjacency rebuilds
**Defect:** `_region_indices_from_hops` and `PlacementContext.nodes_within_hops` are the same algorithm written twice; adjacency is rebuilt from `edge_pairs` three separate times per `generate` (`_assign_archetypes:477`, `_region_indices_from_hops:677`, `_build_placement_context:720`).
**Breaks:** at 800–2500 nodes that's three O(E) allocations of `Array[PackedInt32Array]` per run, and a fix to one BFS (hop counting, self-loop handling) silently misses the other.
**Fix:** build adjacency once right after `_triangulate_and_prune`, thread it through the phases, and keep only `PlacementContext.nodes_within_hops`.

### 14. MEDIUM | procgen/playground/playground_panel.gd:151 | Dev tooling depends on the pipeline's private statics
**Defect:** the panel calls `GraphProcgen._propagate_mask_radius` (×2) and `GraphProcgen._roll_modifiers_v4`, reproducing the per-node loop's two calls by hand.
**Breaks:** the tab's whole value is "what this sample rolls is what generation rolls", and that equality is maintained by copy-paste against underscore-private functions — any phase refactor (finding 1) breaks it silently, and it already diverges (the panel passes `node_index = 0` and an empty `role_tags` for every sample).
**Fix:** expose one public `GraphProcgen.roll_node_content(config, archetype, position, budget, rng) -> Array[StatModifier]` that both the per-node loop and the panel call.

### 15. MEDIUM | procgen/graph_procgen.gd:386 | Connectivity certificate is an `assert`, and the merge invariants say so themselves
**Defect:** the "the skill tree must be one connected component" check is `assert(n - merges == 1, ...)` — stripped in release builds; `StatModifierAggregator._merge:946` carries the same shape plus its own `# TODO: move this to a test`.
**Breaks:** the one structural invariant the entire game rests on is unenforced in exactly the build where a shipped preset would break it, and the TODO's author is right — an assert on merge arguments tests `_merge`'s callers, not its contract, so it belongs in `test/unit/`.
**Fix:** keep the cheap debug assert but add a GUT case over `first_level.tres` asserting one component (there is already `test_procgen_connectivity.gd` to extend), and move `_merge`'s two argument asserts into a unit test of the aggregator.

### 16. NIT | procgen/graph_procgen.gd:888 | 27 lines of commented-out predecessor under a lying docstring
**Defect:** the pre-aggregator implementation sits commented out at lines 888–914 (with its own `# TODO: sort by total cost is better`), directly under a docstring that still promises "emit in first-drawn order so tooltips read top-to-bottom as the draw unwound" — while `get_aggregate()` sorts by descending accumulated cost.
**Breaks:** the comment describing the emitted order is false, and the next reader has to diff two implementations to learn which one runs.
**Fix:** delete the commented block; rewrite the ordering sentence to "descending total cost".

### 17. NIT | procgen/presets/first_level/first_level.tres | Preset drifted from the v4 seed table
**Defect:** `base_min/base_max = 1/3` vs the doc's "base 2..4 … Floor of 2 = no budget-1 dead nodes"; `RandomBudgetBoost.count = 5` vs the doc's 10; the INT debuff is `unit -2, max_tier 3` vs the seed table's `−5, max_T 1`.
**Breaks:** `procgen-v4.md`'s "Budget envelope" section — the numbers #268's balance harness will be calibrated against — describes a preset that no longer exists.
**Fix:** re-derive the envelope paragraph from the shipped values, or restore the values; either way pin base_min in `test_specimen_pool_set.gd` alongside the override-count budget it already guards.

### 18. NIT | procgen/pools/addon_policy.gd:28 | Nine hand-written weighted-pick loops
**Defect:** the same "sum weights, `rng.randf() * total`, walk subtracting" sample appears at `addon_policy.gd:36`, `archetype_policy.gd:64`, `archetype_balancer.gd:57`, `modifier_pool.gd:37`, `spell_grant_roll.gd:52`, and `graph_procgen.gd:616 / 783 / 1000 / 1039` — with three different fallback behaviours on the float-error tail (`keys().back()`, `affordable.back()`, `null`).
**Breaks:** the tail case is where weighted samplers go wrong, and it is currently decided nine times by nine authors; three of the nine also silently differ on whether negative weights are clamped.
**Fix:** one `WeightedPick.from(items, weight_fn, rng)` helper in `procgen/weighting/`, with the tail rule decided once.

### 19. NIT | procgen/graph_procgen.gd:173 | Untyped collections cluster in the pipeline and the playground
**Defect:** 37 bare `Dictionary`/`Array` declarations, concentrated in `graph_procgen.gd` (12 — `fp`, `seen`, `pool`, `tier_rates`, `minted_unique_scenes`, `rt`, `ks`), `playground_panel.gd` (5 — the `sample` / `breakdown` dicts passed between four methods), and `node_graph_view.gd` (4 — three `SkillNode ->` maps).
**Breaks:** `fp` (the `procgen_footprint` meta) and `sample`/`breakdown` are cross-method record types passed by `Dictionary` with string keys — a renamed key fails silently at the read site, and `_fill_card` already defends with `sample.get("budget", 0)`.
**Fix:** `Dictionary[SkillNode, Vector2]` etc. where the map is homogeneous; a small `RefCounted` for the footprint and for the budget breakdown, which `BudgetPolicy.compute_budget_breakdown` and `_breakdown_text` both key into by hand.

### 20. NIT | procgen/pools/stat_pool.gd:94 | The brief's "22 missing return types" in procgen is a false positive
**Defect:** the mechanical sweep counted multi-line `func` signatures whose `-> Type` sits on the closing-paren line. The genuine count in `procgen/` is **one**: `func _update_resource_name():`.
**Breaks:** nothing today, but the 22 figure would send someone on a 40-minute non-hunt.
**Fix:** add `-> void`; re-run the sweep with a signature-aware matcher before quoting the number elsewhere.

### 21. NIT | procgen/pools/stat_pool.gd:180 | Authoring feedback lives where nobody sees it (#349)
**Defect:** `StatPool` / `StatPack` / `ModifierPoolEntry` / `RadialBandProfile` all implement `_get_configuration_warnings`, but Godot surfaces those for *nodes*, not for sub-resources nested three deep in a `.tres` — and every pool in the repo is a `SubResource` inside a pack. The only way to see a pool's resulting numbers is to select the `ModifierPoolSet` and press the "Print pools as tables" button.
**Breaks:** every validator in this directory (tag typos, `unit_value 0`, `max_tier < min_tier`, the debuff rule) is effectively unreachable through normal authoring — which is most of why authoring pools is painful.
**Fix:** for #349, run all `_get_configuration_warnings` from a single `ModifierPoolSet`-level aggregate (walk packs → pools → entries, prefix each line with the pool's `resource_name`) and surface it in the playground's sidebar, so warnings appear on the surface a designer already has open.

---

## Verdict

The *content* model is genuinely well-modelled: `StatPool` + `TierLadder` + `flatten_for_node` is a clean, one-law authoring system, and `placement/` + `weighting/` are small composable resources with real seams. The *pipeline* is not — `graph_procgen.gd` is a 1066-line static function whose phases exist only as local variables, which is why both the tests and the playground reach through its underscore-privates, and why the v3→v4 migration could leave a dead draw path (`_weighted_pick_from`, `ModifierPool`), a dead feedback channel (`already_rolled`), and a self-flagged stub (`StatModifierAggregator`) sitting side by side with the live one. The addon pass is worse: two exported knobs and three paragraphs of docstring describe a budget-and-profiles pipeline that was never implemented. Splitting the six phases into typed objects is the change that makes the rest of these findings cheap to fix — and it is the same change that would let the playground sample through a public contract instead of a copy of the per-node loop.
