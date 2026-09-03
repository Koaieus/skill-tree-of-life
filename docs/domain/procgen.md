# Procgen — engineering reference

Code: `procgen/graph_procgen.gd` (pipeline) + `procgen/graph_procgen_config.gd` (inputs). Static, RefCounted, no in-memory state — every call is a pure function of `(config, graph, rng_seed)`.

## Pipeline

`GraphProcgen.generate(config, graph) -> Dictionary` runs six stages:

1. **Starting-point assembly** — with `config.starting.starter_placement` set (every shipped preset, since #742), it REPLACES the manual list wholesale: `starter_placement.plan(camp_sizes, radius, min_dist, rng, shape_mask, random_starter_max_tries)` (`CampAnnulusStarters` for camp-relative rings, `CenterCoreStarters` for a single centred human plus a rejection-sampled random fill, spacing governed by `StarterPlacement.viability_radius`, a `min_dist` multiplier authored per placement instance). With no `starter_placement` authored, the starter list is `config.starting.starting_points` (hand-authored) verbatim — no random fill on that path any more.
2. **Poisson-disk sample** — `PoissonDiskSampler.sample(shape_mask, min_dist, node_count, anchors, rng)` seeds positions inside the `ShapeMask`, honouring starter anchors. `min_dist = 2·node_radius + node_padding`.
3. **Delaunay triangulate + prune** — `_triangulate_and_prune(positions, connectivity)` builds the planar candidate edge set, then trims to MST + a `connectivity`-controlled share of shortest extras (0 = MST only, 1 = full triangulation).
4. **Archetype assignment** — `_assign_archetypes()` runs a target-driven BFS-grow: `config.archetypes` (`ArchetypePolicy`) each claim a `target_ratio` share of nodes, seeds are placed greedily, then grown through the pruned adjacency; leftovers inherit their nearest claimed neighbour. `cluster_jitter` (per-policy) rerolls afterwards to soften borders. Empty `archetypes` → every node stays archetype-less (and content-less).
5. **Budget + modifier roll** — `config.budget_policy.compute_budget(archetype, position, role_tags, rng)` rolls each node's modifier budget (base range × archetype × positional `budget_field` × role bonuses). `_roll_modifiers_v4()` then spends that budget until broke across the node's archetype + universal pools, aggregating per `(stat_id, operation)` (ADD*/INCREASE sum, MULTIPLY product, SET max). See [procgen-v4.md](procgen-v4.md) for the draw model.
6. **Instantiate** — instances `skill_node/skill_node.tscn` for each position, applies position/radius/modifiers/base_type_color, stamps keystones + rolls addons, and adds it (plus edges) to the `Graph` via the structural-signal API.

> **One content pipeline.** The older v1 (`node_types` + per-`NodeTypeDef` pools), v2 (config-level universal `modifier_pool`), and v3 (phased pool draw) generations were retired — `graph_procgen.gd` now runs a single v4 path (`archetypes` + `budget_policy` + `modifier_pool_set` of flat `StatPool`s, spend-until-broke + per-(stat,op) aggregation). `docs/domain/procgen-v2.md` is kept only for design history (the v3 doc was deleted along with the v3 files, #329).

## Return value

```
{
  "nodes": Array[SkillNode],            # all generated nodes, in poisson order
  "starting_nodes": Array[SkillNode],   # those that landed on starting_points
  "starters": Array[StartingPoint],     # the assembled starter list (manual + random)
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
