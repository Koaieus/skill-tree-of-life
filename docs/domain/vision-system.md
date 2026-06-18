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
  radius is read per-node via `SkillNode.get_local_stat(&"vision_range")`,
  so an addon (e.g. Spyglass) can buff sight on one node without
  touching the entity stat.
- **Sensed set** — graph BFS: every node within `sensor_range` *hops*
  from any allocated node, walking edges through `graph.get_neighbours`.
  Sensed-but-not-visible nodes are queryable (`is_sensed(node)`) but
  stay unpickable.
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
| `_recompute` (CPU) | O(N × S) distance checks + O(S × hops) BFS | per allocation / stat change |
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
