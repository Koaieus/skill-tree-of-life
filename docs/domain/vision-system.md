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
  ├─ pushes circles uniform (vec4[256]) on every render tick
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
  paint has already reached it. Only allocated nodes seed today
  (unallocated nodes are inert traversers — see "Future hooks" below).
  Sensed ∖ visible nodes are queryable (`is_sensed(node)`) and the
  `SkillNode.sensed` flag drives a faint base-type-tinted outline
  render in `NodeVisualsComposite`'s `SensedOutline` component (#141,
  #304) — archetype only, no owner colour, no modifier content.
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

### The vision RULE is one class, shared by every caller (#378)

The scene carries exactly **one** `VisionSystem` instance, and its `viewers`
is normally `[player]` — it drives the player's fog rendering only, not a
general per-entity visibility oracle. AI needs its own per-entity check
("does *this* enemy see a hostile"), which can't be answered by mutating the
shared instance's `viewers` without breaking player fog.

The fix is NOT a second vision implementation. **`VisionCircles`**
(`systems/vision_circles.gd`) holds the circle set *and* the geometry that
reads it: `add(pos, radius)` then `has_point(p)`. The live `_recompute()`
above builds one per pass from `viewers`; `AiRecon`
(`entity/controller/ai_recon.gd`) builds its own from
`Entity.navigator.get_mirrored_nodes()` (the querying entity's own owned
subgraph). `Navigator`/`EntityNavigator` answers *which* nodes to test;
`VisionCircles` answers whether a point is visible — never duplicate the
geometry at a second call site.

**Why it's a class and not the `static is_within_circles(pos, positions, radii)`
it replaced (2026-08-17, lane P):** every caller asks about *many* points
against the *same* circles, so the static forced a per-point linear scan —
O(points × circles). At the scale this project targets (~2000 nodes, ~200
owned) that measured **13.3ms of a 19.4ms recompute**, on every allocation,
against a 6.9ms frame budget at 144Hz. `AiRecon` ran the identical shape per AI
turn. Owning the set lets it carry a **uniform grid**, cell size = largest
radius, so a 3×3 neighbourhood scan is *exact* (a circle can only contain `p`
if its centre is within `max_radius` of `p`) and points outside the union's
bounding box — most of a fogged map — cost four float comparisons. Result:
6.5ms, and recompute cost stopped tracking owned count (25× the owned nodes →
1.75× the cost, was ~5×). Pinned by `test/unit/systems/test_vision_circles.gd`
(indexed answer vs. brute force, including the degenerate sets) and
`test_vision_recompute_scaling.gd` (the cost ratio, and "one allocation → one
recompute").

Two properties any future change here must keep: the bounds test is **inclusive
on all four sides** (`Rect2.has_point` is not — see
`.claude/rules/gdscript-pitfalls.md`), and a **zero-radius circle still
contains its own centre**, because an owned node with no vision must still see
itself.

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

The renderer is a single `Node2D` (`FogOverlay`) that draws one rect
covering the playable area, with a `ShaderMaterial` doing all the work.
No SubViewport, no per-circle sprites.

### Shader: visibility model

`range` (the radius stat) = the **outer edge of any vision** — where
the last visible pixel sits. The fade zone lives INSIDE the radius:

```
[node] ··· 100% clear ··· fade (clear→dark) ··· HALO at d=1.0 ··· pure black
```

Uniforms:

- `circles[256]`: `vec4(world_x, world_y, radius, motion)` per source.
  `motion ∈ [0, 1]` is non-zero while the circle is animating, used
  to brighten the halo at moving frontiers.
- `circle_count: int` — how many of the array slots are populated.
- `intensity: float` — global darkness multiplier (the debug slider).
- `falloff: float` — fade-zone width as a fraction of radius.
  Linear ramp, so `falloff = 0` is a hard edge, `falloff = 1` fades
  from center to edge.
- `glow_band, glow_color, glow_strength` — halo width, tint, and
  intensity. Halo is symmetric ±`glow_band` around d=1.0.

Fragment math is `O(circle_count)` per pixel — one distance + minimum
tracking per circle. At 1080p and 256 circles that's ~500M ops/frame,
single-digit percent of a modern GPU.

### Render-only animation

`_target_radii` (set by `_recompute`, snaps on allocation / stat change)
drives the logical visible set. `_animated_radii` (lerped in `_process`)
drives the rendered uniforms. They're deliberately decoupled — a node
becomes targetable the moment allocation lands, and the fog catches up
visually over the ease.

Per-frame lerp is frame-rate-independent ease-out:
`r = lerp(r, target, 1 - exp(-ease_rate * delta))`. Snap-to-target when
within 0.5 px, drop the entry from `_circles` when target=0 and the
rendered radius retires to ≤ 1 px. `set_process(false)` when no entry
is moving so the system costs nothing while idle.

`vision_render_tick` fires while animating; FogOverlay re-uploads
uniforms on each tick. `visibility_changed` fires only on
recompute — once per logical change.

## Cost model

| Path | Complexity | Frequency |
|---|---|---|
| `_recompute` (CPU) | O(N × S) distance checks + O((N + E) · log-ish) priority traversal | per allocation / stat change |
| `_process` (CPU) | O(\|_circles\|) lerps | per frame while animating |
| Shader (GPU) | O(circle_count) per pixel | per frame while overlay visible |

`N` = total nodes, `S` = active sources (= allocated nodes across all
viewers). At the current scale (entities of ~20 nodes), every path
is comfortable. At 200-node entities the CPU recompute is ~40k
distance checks per event — still trivial since the event rate is
low (allocation, stat change). The shader fragment loop at 256
circles is the most likely first bottleneck if board counts grow much
beyond that.

## Scaling path

When source counts cross ~500+ or we want pre-rasterized occluders /
colored lights, switch to a **render-to-texture** mask:

1. A `SubViewport` matched to world bounds.
2. One `Sprite2D` per circle with a radial-gradient texture, positioned
   and scaled in world coords, additive blend.
3. Fog shader samples the `ViewportTexture` once per fragment — O(1).

Decoupling the per-circle metadata (motion) from the geometric mask
would need either a second mask channel or a side data buffer. Not
trivial; only worth it when uniform-array scaling actually fails.

## Off-switches (composability)

Three independent levers, layered:

1. Remove `VisionSystem` from scene — input pickable stays true,
   no fog, no recompute. Hard off.
2. Remove `FogOverlay` only — input gating still active, just no
   visible darkness. Useful for testing logical gating.
3. `viewers = []` + `empty_mode = OFF` — system is wired but inert,
   all nodes visible. `FogOverlay.visible = false` (no fullscreen pass).

## Future hooks (sensor mechanics)

The priority-traversal shape leaves two natural extension points open;
neither is wired today, both are worth noting before someone reinvents
them ad-hoc.

- **Signal blockers** — per-node hop cost. Today every edge step costs
  1 budget. A node could carry a `sensor_hop_cost` local stat (default
  1, blockers raise it to 2/3/N); the traversal would subtract
  `nb.get_local_value(&"sensor_hop_cost")` instead of a constant
  1 when expanding into `nb`. Falls out of the existing
  `best_remaining` dominance check unchanged.
- **Unallocated re-radiating boosters** — a signal repeater that an
  enemy hasn't claimed yet but still amplifies any probe passing
  through. On expansion into `nb`, take `max(remaining_after_hop,
  nb.get_local_value(&"sensor_radiate_range"))` as the new
  budget (capped at most once to avoid runaway). Owned re-radiators
  are degenerate — they're already seeds with their own budget.

Both are pure traversal tweaks: no new signals, no new render state,
no schema migration. Don't pre-build either until a mechanic actually
calls for it.

## Sensed render rules

When `SkillNode.sensed` flips on, `_apply_sensed_state` does three
things in one pass:

1. `NodeVisualsComposite.sensed` switches to outline-only: it hides its
   shader stack (InnerDisk/RimRing/CorePresence) and shows `SensedOutline`
   (faint base-type-tinted ring only).
2. `z_as_relative = false` + `z_index = 1001` lifts the node above the
   fog overlay (which lives at `z_index=1000`) so the outline isn't
   dimmed into nothing. The exact z is a knob — bump both if the fog
   overlay's z changes, or if some other UI layer wants to live in
   between.
3. `core_marker` and every attached addon are hidden. The viewer
   shouldn't learn ownership-vs-not-ownership of the core, nor which
   addons sit on the node, from a sensed read.

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

An edge is sensed iff **both endpoints are reached** (visible or
sensed) **and at least one is sensed-only**. Both-visible edges render
normally (lit/unlit by ownership); edges with one unreached endpoint
stay hidden behind fog. The "at least one sensed-only" clause keeps
two clear-vision endpoints on the normal lit/unlit path even if their
edge would also be sensed-by-definition — sensed treatment is for the
fog backdrop, not the clear one.

`Edge.sensed` mirrors the SkillNode pattern: written by VisionSystem
after the node sets are computed, the setter z-promotes the edge above
the fog (`z_as_relative=false`, `z_index=1001`) so the topology
breadcrumb reads through, and `_draw` switches to the unlit colour at
70% alpha and 75% width — never the lit colour, even if both endpoints
happen to share owner. Owner identity is above the topology gate.

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
- **Per-element dimming, not per-fragment.** FogOverlay z-promotes
  visible nodes + edges above the fog (z=1001) and modulates their alpha
  by the fog darkness sampled at their CENTER (`_sample_dark`,
  `_apply_per_element_dimming`). Otherwise the per-fragment fog gradient
  bisects any disk sitting in the fade zone — half clear, half pure
  black — and that "half-shaded" disk reads darker than a fully-sensed
  neighbour in pitch darkness. A `_VISIBLE_DIM_FLOOR` (= sensed outline
  alpha) keeps the visible → sensed transition continuous: a node never
  dims below the floor a sensed render would give it. Edges sample at
  their midpoint; only both-endpoints-visible edges are lifted (a
  one-visible-one-hidden edge stays at z=0 so fog covers its hidden half
  naturally). Cost: O(N + E) per render tick, alongside the uniform
  upload.
