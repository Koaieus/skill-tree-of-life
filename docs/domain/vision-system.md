# Vision System

Fog-of-war + line-of-sight gating for the skill-tree graph. Lives in
`systems/vision_system.gd` (logic) + `ui/fog_overlay/` (renderer +
shader). Designed so removing either node from the scene gracefully
degrades — input still works without the renderer, all-visible mode
without the system at all.

## Layering

```
VisionSystem (Node, sibling to AllocationSystem under Graph)
  ├─ owns: logical visibility + sensor sets, animated render state
  ├─ drives: SkillNode.input_pickable (single lever for input gating)
  └─ signals: visibility_changed (logical), vision_render_tick (per-frame)

FogOverlay (Node2D + canvas_item ShaderMaterial)
  ├─ subscribes to both signals
  ├─ packs sources into data textures + a tile grid on every render tick
  └─ hides entirely when VisionSystem.should_render_fog() is false
```

The split keeps gameplay-relevant state (who can see what, what's
clickable) decoupled from cosmetics (fog drawing, halo animation). Attack
plans, allocation, and tooltip code never need to query the renderer.

## Logical visibility

Per-entity, derived from each allocated node:

- **Visible set** — Euclidean: every node whose `global_position` is
  within `vision_range` of any of the viewer's allocated nodes. The
  radius is read per-node via `SkillNode.get_local_value(&"vision_range")`,
  so an addon (e.g. Spyglass) can buff sight on one node without
  touching the entity stat.
- **Sensed set** — graph priority traversal. Every owned node seeds a
  probe with its own *local* `sensor_range` (read via
  `SkillNode.get_local_value(&"sensor_range")`, so an addon — e.g. a
  Sensor Tower — can pump reach on one node only). Probes pop
  highest-budget-first; a node already reached with budget ≥ B can't be
  improved by a later, weaker probe and is skipped without expansion.
  A +3 tower next to a +0 neighbour therefore *dominates* the
  neighbour's seed: by the time that 0-budget probe pops, the tower's
  paint has already reached it. Only allocated nodes seed (unallocated
  nodes are inert traversers). Sensed ∖ visible nodes are queryable
  (`is_sensed(node)`) and the `SkillNode.sensed` flag drives a faint
  base-type-tinted outline render in `NodeVisualsComposite`'s `SensedOutline`
  component — archetype only, no owner colour, no modifier content.
- **Viewers** are an `Array[Entity]`. Multiple viewers compose their
  sets via union. Empty array + `empty_mode = ALL_ENTITIES` falls back
  to `group("entities")` — Entity self-joins that group at edit time
  and runtime.

`empty_mode` enum controls the empty-viewers behavior:

| Mode | Behavior |
|---|---|
| `OFF` (default) | All nodes marked visible. System inert. |
| `DARKNESS` | Nothing visible. Pure fog. |
| `ALL_ENTITIES` | Effective viewers = group("entities") sweep. |

### The vision RULE is one class, shared by every caller

The scene carries exactly **one** `VisionSystem` instance, and its `viewers` is the
**camp-mates** — every entity, AI or human, sharing the bound hero's `faction.id`. The
rule lives in `SeatPolicy.vision_group` (`session/seat_policy.gd`, see
[seat-policy.md](seat-policy.md)); `GameRoot` supplies the candidates in group order
and writes the result (`_apply_seat_vision`). In single player that is `[player]`; in
hot-seat coop it is both allied humans, so handing the turn over does not re-derive
fog from a different owned subgraph and flash the map. In versus — local or online —
rivals are on different camps, so each hero's group is itself and a hot-seat handover
swaps the fog. Blockers sit on their own camp and are never viewers. Assigning
`viewers` unconditionally rebinds and recomputes, so the setter is only written when
the set actually changed — the equality is element-wise, so the candidate walk must
stay in a stable order. This drives the local fog rendering only, not a general
per-entity visibility oracle: AI needs its own per-entity check ("does *this* enemy
see a hostile"), which can't be answered by mutating the shared instance's `viewers`.


The fix is NOT a second vision implementation. **`VisionCircles`**
(`systems/vision_circles.gd`) holds the circle set *and* the geometry that
reads it: `add(pos, radius)` then `has_point(p)`. The live `_recompute()`
above builds one per pass from `viewers`; `AiRecon`
(`entity/controller/ai_recon.gd`) builds its own from
`Entity.navigator.get_mirrored_nodes()` (the querying entity's own owned
subgraph). `Navigator`/`EntityNavigator` answers *which* nodes to test;
`VisionCircles` answers whether a point is visible — never duplicate the
geometry at a second call site.

**Which discs, one answer: `VisionSystem.sources_for(viewers)`.** It returns
`Array[VisionSource]` (`systems/vision_source.gd`, RefCounted: `node`, `center`,
`radius`, `kind`), pure — it reads the graph and the nodes' scout rows, never the eased
`_circles`. Kinds: `OWNED` (each node a viewer owns, at its local `vision_range`) and
`SCOUT` (each node holding a `scout` row keyed by a viewer's camp, at
`ScoutStatus.radius_for(node, power)`). `_recompute()` builds its `VisionCircles` *and*
its `_circles` fog targets from `sources_for(_effective_viewers())` — there is no
second gathering path; `get_vision_sources()` is the fog's eased, local-view render
list built on those targets. A new kind of sight is one `Kind` value plus one gather
branch in `sources_for`. `AiRecon` still gathers its own owned nodes.


**Why a class and not a static `is_within_circles(pos, positions, radii)`:** every
caller asks about *many* points against the *same* circles, so owning the set lets it
carry a **uniform grid**, cell size = largest radius, so a 3×3 neighbourhood scan is
*exact* (a circle can only contain `p` if its centre is within `max_radius` of `p`)
and points outside the union's bounding box cost four float comparisons — recompute
cost stops tracking owned count. Pinned by `test/unit/systems/test_vision_circles.gd`
(indexed answer vs. brute force) and `test_vision_recompute_scaling.gd` (the cost
ratio, and "one allocation → one recompute").

Two properties any future change here must keep: the bounds test is **inclusive on
all four sides** (`Rect2.has_point` is not — see `.claude/rules/gdscript-pitfalls.md`),
and a **zero-radius circle still contains its own centre**, because an owned node with
no vision must still see itself.

## Scout discs from rows

A scout disc is a **node status**: the scout arrow (`attack/ammo/types/scout.tres`,
`damage_scale` 0) is a zero-damage carrier whose one rider lands one stack of
`effects/status/scouted.tres` (a `ScoutStatus`, id `scout`) on the target — the
common `compute` + `riders_for` path, gated like any arrow (a dud on a node no longer
hostile). The affected node grants vision to the camp of the firer, one stack per
arrow. Rows are grouped by `camp_id`, so each camp holds its own count; a row decays
one stack on the host owner's turn end like any node status, and rides the
`AttackRecord` as a plain `STATUS` hit, so a peer lands the same row.

- **The read.** `sources_for` checks every node in its one graph pass for a
  `scouted_def` row whose key is any viewer's camp (`Faction.id`, `&""` for none) and
  adds a `SCOUT` source at `scouted_def.radius_for(node, power)` (the strongest such
  row). `_recompute` feeds those into the same `VisionCircles` index and `_circles`
  fog targets as owned discs; a scout source `max`es against an owned circle on the
  same node. Another camp's rows draw nothing, so a hostile scout leaks nothing.
- **The trigger.** Each node's own `SkillNode.statuses_changed` (apply, tick, removal
  — live and on a peer's replay), connected per node at `_ready` and on
  `graph.node_added`. The handler requests a recompute only if the node holds a
  viewer-camp scout row now or drew a scout disc at the last recompute
  (`_scout_nodes`), so a poison tick elsewhere never recomputes the fog.
- **Per-node feedback.** `SkillNode.scouted` is written beside `sensed`/`revealed`
  from the same read (true iff the node drew a scout disc for the local view); it
  drives a lazily-instanced `skill_node/visuals/scout_marker.tscn` ring. The scouted
  side sees the row's presence through its status readout, not this ring.
- **`pick_sensed`.** An `@export` marker: when true, `input_pickable = visible or
  sensed`. Toggled by the scout shot while a scout-armed ranged plan is live; default
  false. A scout type is `AmmoType.is_scout()` (a `ScoutStatus` rider) — the one
  predicate the shot, the composer and the armed mode read.

Tests: `test/unit/systems/test_vision_scout_marks.gd`,
`test/unit/systems/test_vision_sources.gd`, `test/unit/attack/test_scout_arrow.gd`.

## Input gating

One lever: `SkillNode.input_pickable = is_visible(node)` toggled per
recompute. Consequences fall out for free:

- `mouse_entered` doesn't fire → no `Events.skill_node_hovered.emit` →
  no tooltip
- `_on_input_event` doesn't fire → no `left_clicked` / `right_clicked`
  → no attack targeting, no allocation

`attack_plan.gd`, `player_input_controller.gd`, and tooltip code need
zero changes. There's no `if visible:` scattered through consumers; the
Area2D physics layer enforces the policy.

When `VisionSystem` is removed from the scene, no recompute ever runs
→ `input_pickable` stays at its default (`true`) → all nodes are
trivially pickable. Graceful degradation.

## Render path

`FogOverlay` is a single `Node2D` that draws one rect covering the playable area
with a `ShaderMaterial` (`ui/fog_overlay/fog.gdshader`). The circle-union darkness
field lives in `ui/vision_field.gdshaderinc` as **global uniforms**, shared by every
self-shading consumer; `FogOverlay` is its sole writer
(`RenderingServer.global_shader_parameter_set`).

### Data and shader: visibility model

Each render tick `FogOverlay.set_sources` hands the sources to a `VisionSourceIndex`
(wrapping `OverlayFieldTileIndex`), which packs them into data textures plus a
world-space tile grid (cell size = reach, so a 3×3 tile neighbourhood is exact):

- `vision_circles_tex` — `(world_x, world_y, radius, motion)` per source. `motion ∈
  [0, 1]` is non-zero while the circle animates, brightening the halo at moving
  frontiers.
- `vision_tile_index_tex` / `vision_tile_indices_tex` — per tile, the offset and count
  of the circles that can reach it.
- `vision_grid_origin`, `vision_cell_size`, `vision_grid_cols/rows`,
  `vision_circle_count`, `vision_falloff`, `vision_union_smoothness`,
  `vision_field_enabled`.
- Material uniforms: `intensity` (global darkness multiplier), `glow_band`,
  `glow_color`, `glow_strength` (halo, symmetric ±`glow_band` around d=1.0).

`range` (the radius stat) is the **outer edge of any vision**; the fade zone lives
INSIDE the radius, with `falloff` the fade width as a fraction of the radius:

```
[node] ··· 100% clear ··· fade (clear→dark) ··· HALO at d=1.0 ··· pure black
```

The fragment shader walks the 3×3 tile neighbourhood and smooth-mins the normalised
distances, so its cost is independent of total circle count.


### Render-only animation

`_circles[node] = {radius, target}`: `target` (set by `_recompute`, snaps on
allocation / stat change) drives the logical visible set; `radius` (lerped in
`_process`) drives the rendered circles. They are deliberately decoupled — a node
becomes targetable the moment allocation lands, and the fog catches up visually over
the ease.

Per-frame lerp is frame-rate-independent ease-out:
`r = lerp(r, target, 1 - exp(-ease_rate * delta))`. Snap-to-target when within
0.5 px, drop the entry from `_circles` when target=0 and the rendered radius retires
to ≤ 1 px. `set_process(false)` when no entry is moving so the system costs nothing
while idle.

`vision_render_tick` fires while animating; FogOverlay re-uploads on each tick.
`visibility_changed` fires only on recompute — once per logical change.

## Cost model

| Path | Complexity | Frequency |
|---|---|---|
| `_recompute` (CPU) | O(N × S) distance checks + O((N + E) · log-ish) priority traversal | per allocation / stat change |
| `_process` (CPU) | O(\|_circles\|) lerps | per frame while animating |
| `FogOverlay.set_sources` (CPU) | rebuild the tile grid + data textures | per render tick |
| Shader (GPU) | O(circles in a 3×3 tile neighbourhood) per pixel | per frame while overlay visible |

`N` = total nodes, `S` = active sources (= allocated nodes across all viewers).
The recompute event rate is low (allocation, stat change).

## Scaling

Rendering is already texture-based: cost is per fragment over the few circles in a
tile neighbourhood, independent of total source count. The cap is `_MAX_CIRCLES`
(20000); overflow is truncated loudly (`FogOverlay` warns once) because the overlay
and every self-shading consumer must read the SAME set.

## Off-switches (composability)

Three independent levers, layered:

1. Remove `VisionSystem` from scene — input pickable stays true,
   no fog, no recompute. Hard off.
2. Remove `FogOverlay` only — input gating still active, just no
   visible darkness. Useful for testing logical gating.
3. `viewers = []` + `empty_mode = OFF` — system is wired but inert,
   all nodes visible. `FogOverlay.visible = false` (no fullscreen pass).

## Sensed render rules

When `SkillNode.sensed` flips on, `_apply_sensed_state` does three things in one
pass:

1. `NodeVisualsComposite.sensed` switches to outline-only: it hides the shader stack
   (InnerDisk/RimRing/CorePresence) and shows `SensedOutline` (faint base-type-tinted
   ring only).
2. `z_as_relative = false` + `z_index = ZLayers.GRAPH_DEFAULT + ZLayers.SENSED`
   (`ui/z_layers.gd`) lifts the node above the fog overlay so the outline isn't dimmed
   into nothing.
3. Every attached addon and the core health bar are hidden (the core look is nested
   under the hidden shader stack). The viewer shouldn't learn ownership of the core,
   nor which addons sit on the node, from a sensed read.

The hide in (3) is a **global** rule — every sensed node hides every
addon and the core marker, regardless of viewer. The intended next
layer is per-viewer info gating: each gate (existence, archetype,
owner, modifiers, addons, HP, …) opens independently, and `sensed: bool`
becomes a derived view of "info level for the local viewer is
sensed-or-higher." Full vision then becomes "all gates open" on the
same surface, not a separate code path. See
[../design/info_gating.md](../design/info_gating.md) for the dimensions
roster, default profiles (Hidden / Sensed / Scouted / Identified /
Vision), and the ergonomics requirements that should land first.

## Sensed edges

An edge is sensed iff **both endpoints are reached** (visible or sensed) **and at
least one is sensed-only**. Both-visible edges render normally (lit/unlit by
ownership); edges with one unreached endpoint stay hidden behind fog. The "at least
one sensed-only" clause keeps two clear-vision endpoints on the normal path.

`Edge.sensed` mirrors the SkillNode pattern: written by VisionSystem after the node
sets are computed. Edges render through a MultiMesh and **take no z_index write**
(`graph/edge.gd`): `sensed` selects the `VIS_SENSED` state, drawn in the unlit colour
at `sensed_alpha` (0.35) — never the lit colour, even if both endpoints share an
owner. Owner identity is above the topology gate.

## Gotchas

- **`SkillNode.input_pickable` toggling is the contract.** Don't
  bypass it with manual hover wiring; you'll miss visibility gating.
- **Animation is render-only.** `is_visible(node)` uses the LOGICAL
  target radius, not the animated one — so attack targeting stays
  consistent across the ease. Don't mix the two.
- **Halo only paints when `motion > 0`.** Static circles don't glow.
  If you want a persistent "frontier" effect for, say, an enemy outline,
  use a separate sprite — don't hijack `motion`.
- **Falloff lives inside the radius.** A node at d=0.99 from a source
  is logically visible (clickable) but visually mostly dark. UX
  tradeoff: bias falloff small (≤ 0.15) so the gap between "I can see
  it" and "I can click it" stays narrow.
- **Per-fragment self-shading, and FogOverlay only classifies.** Every element
  that has to dim reads `vision_field_darkness(world_pos)` itself, per fragment,
  from the shared globals in `ui/vision_field.gdshaderinc`: edges in
  `edge_mesh.gdshader`, SkillNode's disk and rim in `inner_disk.gdshader` /
  `rim_ring.gdshader`. `FogOverlay._apply_visibility_classification` has one job —
  stamp a z band on each node (visible → `ZLayers.GRAPH_DEFAULT + ZLayers.SENSED`, so
  it punches through the fog quad; hidden → `GRAPH_DEFAULT`, so the fog paints over
  it) and a `vision_visible` boolean on each edge (OR over its endpoints, so an edge
  straddling the boundary still renders and fades on its own).

  The dim floor is `VISION_VISIBLE_DIM_FLOOR` (0.30) in that same include; it keeps
  the visible → sensed transition continuous: a visible element never dims below the
  alpha a sensed render would give it.

  **The classification hangs off `visibility_changed`, never `vision_render_tick`.**
  It is O(N + E); run per frame it was a sustained framerate drop on a 2000-node
  map. It can live on the rarer signal because logical visibility is computed from
  TARGET radii: an animating circle changes which pixels are lit, never which nodes
  are visible. See `test/perf/bench_fog_refresh_cost.gd` and
  `test/unit/ui/test_fog_overlay_classification.gd`.

  **`FogOverlay` is `@tool`, so what the classifier writes can get BAKED into a
  hand-authored scene** by an editor save with a live fog (the derived-value trap in
  `.claude/rules/gdscript-pitfalls.md`). A baked `modulate` is permanent dimming —
  nothing writes `modulate` any more. If you save a fog-bearing scene with fog live,
  re-check the diff.

  A node's non-shader children — the core look, HoverRing, the health bars, addons —
  do not dim at all; they are core-gated, under the cursor, or on a node the player
  is already looking at.
