# Procgen — engineering reference

Code: `procgen/graph_procgen.gd` (pipeline) + `procgen/graph_procgen_config.gd` (inputs). Static, RefCounted, no in-memory state — every call is a pure function of `(config, graph, rng_seed)`.

## Pipeline

`GraphProcgen.generate(config, graph) -> Dictionary` runs six stages:

1. **Starting-point assembly** — `config.starting_points` (hand-authored) come first; `_place_random_starters()` rejection-samples up to `n_random_starters` more, each ≥ `viability_radius` from existing anchors. Manual entries always precede random entries in the returned list, so callers can split them by index if needed.
2. **Poisson-disk sample** — `PoissonDiskSampler.sample(shape_mask, min_dist, node_count, anchors, rng)` seeds positions inside the `ShapeMask`, honouring starter anchors. `min_dist = 2·node_radius + node_padding`.
3. **Delaunay triangulate + prune** — `_triangulate_and_prune(positions, connectivity)` builds the planar candidate edge set, then trims to MST + a `connectivity`-controlled share of shortest extras (0 = MST only, 1 = full triangulation).
4. **Type assignment** — `_assign_types()` does Voronoi-on-cluster-seeds with `cluster_jitter`. Each node lands in one of `config.node_types` (`NodeTypeDef`).
5. **Modifier roll** — `_roll_modifiers(type_def, budget_scale, rng)` draws from the type's `ModifierPool`. `budget_scale` is `config.budget_field.sample(position)` if set, else 1.0 — so a `RadialGradientField` etc. can make the centre richer than the rim.
6. **Instantiate** — instances `skill_node/skill_node.tscn` for each position, applies position/radius/modifiers/base_type_color, and adds it (plus edges) to the `Graph` via the structural-signal API.

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

Levels that override fields on the preset (`procgen_play_sandbox` overrides `node_count`, `n_random_starters`, `viability_radius`) duplicate the preset before mutating it — otherwise the on-disk `.tres` resource accumulates the overrides across sessions (since Godot caches resources by path). One preset can then serve multiple sandboxes at different sizes without leaking state.

## Extending — adding a field theme

1. New `NodeTypeDef` (`.tres`) with id, colour, and a `ModifierPool` of `ModifierPoolEntry` rows.
2. Append to the preset's `node_types`.
3. (Optional) Give it a non-uniform `budget_field` (any `ScalarField` subclass — `RadialGradientField`, `ConstantField`, custom).

No code change in `graph_procgen.gd` is required for new themes — the pipeline reads everything off the config.

## Caveats

- Generation is **synchronous** in `_setup_level` — no progress UI. Node counts past ~2000 may take >100ms; chunk or defer if that becomes a problem.
- `shape_mask` is required; the assert fires immediately if null.
- `seed = 0` reseeds randomly per run (`randi()`), so non-zero seeds are reproducible.
- The pipeline depends on `Graph.add_skill_node` / `add_edge` emitting signals — Navigator and any other structural listener will fire `node_count + edge_count` times during a single `generate()` call. Acceptable for level boot; not for hot path.
