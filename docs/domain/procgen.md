# Procgen — engineering reference

Code: `procgen/graph_procgen.gd` (pipeline) + `procgen/graph_procgen_config.gd` (inputs). Static, RefCounted, no in-memory state — every call is a pure function of `(config, graph, rng_seed)`. `generate()` never writes to the config it is handed: it resolves on its own copy (auto-scaled `shape_mask`, mask radius handed to every `ScalarField` via `GraphProcgenContent.scalar_fields()` → `ScalarField.resolve_mask_radius`) and returns that copy as `"config"`. Reading a resolved value — the scaled mask, a back-filled gradient — means reading `result.config`, never the argument.

## Pipeline

`GraphProcgen.generate(config, graph) -> Dictionary` runs six core stages (plus the passes listed after them):

1. **Starting-point assembly** — with `config.starting.starter_placement` set (every shipped preset) it REPLACES the manual list wholesale: `starter_placement.plan(camp_sizes, radius, min_dist, rng, shape_mask, random_starter_max_tries)` (`CampAnnulusStarters` for camp-relative rings, `CenterCoreStarters` for a single centred human; the random fill is rejection-sampled inside `plan`, spacing governed by `StarterPlacement.viability_radius`, a `min_dist` multiplier authored per placement instance). With no `starter_placement`, the starter list is `config.starting.starting_points` verbatim, with no random fill.
2. **Poisson-disk sample** — `PoissonDiskSampler.sample(shape_mask, min_dist, node_count, anchors, rng)` seeds positions inside the `ShapeMask`, honouring starter anchors. `min_dist = 2·max_node_radius() + node_padding` — sized once, for the *largest* radius any node can carry (the `node_radius_ramp` asymptote when the topology authors one, else the uniform `node_radius`), so a per-node radius never breaks the spacing invariant.
3. **Delaunay triangulate + prune** — `_triangulate_and_prune(positions, connectivity)` builds the planar candidate edge set, then trims to MST + a `connectivity`-controlled share of shortest extras (0 = MST only, 1 = full triangulation).
4. **Archetype assignment** — `_assign_archetypes()` runs a target-driven BFS-grow: `config.archetypes` (`ArchetypePolicy`) each claim a `target_ratio` share of nodes, seeds are placed greedily, then grown through the pruned adjacency; leftovers inherit their nearest claimed neighbour. `cluster_jitter` (per-policy) rerolls afterwards to soften borders. Empty `archetypes` → every node stays archetype-less (and content-less).
5. **Budget + modifier roll** — `config.budget_policy.compute_budget(archetype, position, role_tags, rng)` rolls each node's modifier budget (base range × archetype × positional `budget_field` × role bonuses). `_roll_modifiers_v4()` then spends that budget until broke across the node's archetype + universal pools, aggregating per `(stat_id, operation)` (ADD*/INCREASE sum, MULTIPLY product, SET max). See [procgen-v4.md](procgen-v4.md) for the draw model.
6. **Instantiate** — instances `skill_node/skill_node.tscn` for each position, applies position/radius/modifiers/base_type_color (with a `node_radius_ramp` on the topology, `base_radius = topology.radius_for_budget(budget)` — 28px @ budget 1, +1px per unit to the knee, a soft asymptote past it — and `base_inner_radius = base_radius − 8`; budget 0 / no ramp = the uniform `node_radius`; an authored landmark scene bypasses the ramp entirely, #330), rolls addons, and adds it (plus edges) to the `Graph` via the structural-signal API.

**Passes around the six stages.** `_apply_archetype_stamps` (territory stamps) overrides archetype assignments after stage 4; `_build_placement_context` + `guaranteed_placements` run before the roll (below); `_place_blocker_indices` / `_roll_blocker_stakes` / `_place_blocker_footprints` plan the removable blockers from a salted RNG; per node, `_roll_subtype` picks the node subtype, `_roll_and_attach_addons` rolls addons (`AddonPolicy.slot_count_weights` → `AddonPool`, independent of the modifier budget), and the spell-grant roll (`procgen/spell_grant_roll.gd`) distributes grants over the INT nodes.

**Placement stage (between 4 and 5) — `ScenePlacement`.** After archetype assignment, every `config.content.guaranteed_placements` entry gets `apply(PlacementContext)` in authored order. `ScenePlacement` is the procgen-side surface for a hand-authored keystone scene (an inherited scene of `skill_node/keystone/keystone_skill_node.tscn`): `node_scene` + `min_count`/`max_count` (uniform inclusive draw) + `weight: ScalarField` (null = uniform; a sample ≤ 0 is never a candidate) + `exclude_starters` / `min_hops_from_starter` / `role_tag`, authored on the *preset* — a scene knows nothing about how often it appears. It writes `PlacementContext.scenes[i]`; the instantiate loop then instantiates THAT scene as node `i` and treats it as **pure**: position + `role_tags` meta and nothing else — no archetype, no budget, no `_roll_modifiers_v4`, no rolled addons, no radius stamp (the authored radius stands), never a blocker core or footprint, never in the spell-grant pool. Draws come off `PlacementContext.scene_rng` (`rng.seed + _SCENE_RNG_SALT`, the blocker pass's precedent) so the main stream is byte-identical with or without scene placements and every peer reproduces the picks — but because a pure node skips the modifier roll, every draw *after* the first placed node shifts on the main stream, which is why adding a placement to a preset moves its golden. First entry wins a slot; a later placement never overwrites a filled `scenes[i]`.

> **One content pipeline.** `graph_procgen.gd` runs a single path: `archetypes` + `budget_policy` + `modifier_pool_set` of flat `StatPool`s, spend-until-broke + per-(stat,op) aggregation. [procgen-v4.md](procgen-v4.md) is the content reference.

## Content building blocks

- **`WeightProfile`** (`procgen/weighting/`) — `multiplier_for(entry, WeightContext) -> float`; profiles multiply into a pick's weight. `WeightContext` is a per-node bag (archetype, position, degree, `forbid_tags`, …) built once per node and read unchanged by every pick; profiles read only what they need. `ArchetypeWeightProfile.weights` is `archetype → tag → multiplier` (an unlisted tag or archetype is 1.0); `forbid_tags` on the `ArchetypePolicy` zero an entry before any profile runs.
- **`BudgetPolicy`** (`procgen/budget/`) — `max(1, round(lerp(base_min, base_max, rng) × archetype_multiplier × budget_field(position) × Π role_bonus))`; the live numbers are in the preset's `content.tres`.
- **`AddonPolicy` / `AddonPool`** (`procgen/pools/`) — the addon roll; its `weight_profiles` are not applied today.
- **`GuaranteedPlacement`** (`procgen/placement/`) — pre-roll constraints on the `PlacementContext`: `MinNearStartingPoints` (role-tags ≥N nodes within K hops of every starter), `RandomBudgetBoost`, `ScenePlacement`.
- **`ArchetypeBalancer`** (`procgen/archetypes/`, off by default) — Pittman-style rebalance of the cluster-seed pick: weight `× (target_ratio − current_ratio + strength_epsilon)`, `target_ratio` read off each `ArchetypePolicy`; small epsilon = strict ratios.
- **Tags** — every tag on a pool entry or profile is declared in `procgen/archetypes/tags.tres` (`TagRegistry`); the `@tool` configuration warnings and `test/unit/test_procgen_tags.gd` flag an unknown one.

## Return value

```
{
  "nodes": Array[SkillNode],            # all generated nodes, in poisson order
  "starting_nodes": Array[SkillNode],   # those that landed on starting_points
  "starters": Array[StartingPoint],     # the assembled starter list (`starter_placement.plan` output, else `starting_points`)
  "blockers": Array[Dictionary],        # removable-blocker plan (absent on the zero-node early return)
  "config": GraphProcgenConfig,         # what generation resolved — a copy; the caller's config is untouched
}
```

`starting_nodes[i]` corresponds to `starters[i]` — caller wires entity cores by index.

## Starter group convention

Levels that consume procgen output should also tag starting nodes into group `&"procgen_starter"`, so downstream consumers (placement systems, dev overlays, AI-spawning logic) can pull starters without re-deriving them from the return dict. `procgen_play_sandbox.gd` does this in `_setup_level`:

```gdscript
for n in starting_nodes:
    n.add_to_group(&"procgen_starter")
```

## Why `preset.duplicate(true)`

Levels that override fields on the preset (`procgen_play_sandbox` overrides `node_count`, `camp_sizes`) duplicate the preset before mutating it — otherwise the on-disk `.tres` resource accumulates the overrides across sessions (since Godot caches resources by path). One preset can then serve multiple sandboxes at different sizes without leaking state.

## Extending — adding an archetype theme

1. New `ArchetypePolicy` (`.tres` or sub-resource) with `id`, `color`, `primary_stat`, a `target_ratio`, and `cluster_size_weights`.
2. Append it to the preset's `archetypes`.
3. Make sure `modifier_pool_set` carries `StatPack`s whose `StatPool`s match the new `primary_stat` (or are universal, `archetype_stat == &""`), so the v4 draw has content to pull for that archetype.
4. (Optional) Shape budget via `budget_policy` — `archetype_multiplier[id]` for a per-archetype scale, or a positional `budget_field` (any `ScalarField` subclass) for a spatial gradient.

No code change in `graph_procgen.gd` is required for new themes — the pipeline reads everything off the config.

## Caveats

- Generation is **synchronous by default**; pass a `progress_cb` Callable to `generate()` to make it a coroutine that emits `[0,1]` progress and yields a frame per stage (see `procgen_play_sandbox` driving `SceneTransition.progress_bar`). Callers that pass `progress_cb` must `await`.
- `shape_mask` is required; the assert fires immediately if null.
- `seed = 0` reseeds randomly per run (`randi()`), so non-zero seeds are reproducible.
- The pipeline depends on `Graph.add_skill_node` / `add_edge` emitting signals — Navigator and any other structural listener will fire `node_count + edge_count` times during a single `generate()` call. Acceptable for level boot; not for hot path.
