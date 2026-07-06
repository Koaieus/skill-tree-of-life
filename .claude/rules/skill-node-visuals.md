# SkillNode visuals — ring band convention (#67)

How the concentric rings around a `SkillNode` are sized. One convention, one
formula, so radii stay legible "going forward" instead of each ring re-deriving
its own.

## SkillNode-visuals-v2 (milestone #16) — a parallel system, not a cutover

`skill_node/visuals/` holds a new component family (`SkillNodeVisual` /
`SkillNodeRingVisual` base classes in that same directory, plus `inner_disk`,
`weld_symbol`, `rim_ring`, `rim_bonuses`, `core_halos`, `rune_ring`,
`node_visuals_composite`) implementing the 6 locked-pick visuals from
`docs/design/handoff_skill_nodes_visuals/Handoff Prep.dc.html`. It lives
**alongside** `base_circle.gd` / `hover_ring.gd` / `core_marker.gd`, not in
place of them — cutting the live SkillNode render path over to it is an
explicit future decision, not part of this milestone. Preview all components
+ the composite together via the sandbox host's "Node Visuals" tab
(`addons/sandbox_host/tabs/15_node_visuals_tab.tscn` → `skill_node/visuals/panel/node_visuals_panel.tscn`).
`SkillNodeRingVisual.ring_centerline()` delegates to `SkillNode.ring_centerline`
(this file's formula) rather than forking it — keep it that way.

### Shader materials: shared + `instance uniform`, not `resource_local_to_scene`, when possible

`inner_disk` and `rim_ring` (on its 4 built-in presets) each use ONE shared
`ShaderMaterial` (built lazily, cached in a `static var`) across every node
instance, varying per-node via `instance uniform`s in the shader +
`CanvasItem.set_instance_shader_parameter()` in the script. This keeps every
node on screen batching into a single draw call. **Prefer this over
`resource_local_to_scene = true` on a per-node-duplicated material** whenever
every varying value is a plain scalar/vector/color — samplers can't be
instance uniforms, that's the only thing that forces the duplicate-material
escape hatch (see `rim_ring`'s custom-Curve fallback, gated on
`_use_custom_curve`, which bakes a small LUT texture into a dedicated
`resource_local_to_scene` material for just that one instance).

`rim_ring` carries NO knowledge of the disk beneath it — it only owns its own
`inner_radius`/`outer_radius` band (base class) plus an interior `crest_r`
control point marking where the flat floor ends and the bevel to the rim
begins. `node_visuals_composite.gd` is the one layer that knows both InnerDisk
and RimRing exist; it lines `RimRing.inner_radius` up with `InnerDisk.disk_radius`
so the two abut, rather than RimRing reaching for disk-shaped exports itself.

`weld_symbol` does NOT use a blend-mode material — an earlier version drew a
flat white fill under `CanvasItemMaterial.BLEND_MODE_MUL`, which read as a
black sticker whenever the underlying disk was dark (unallocated), since MUL
against a dark destination just darkens further. It now evaluates the SAME
shading formula as `inner_disk.gdshader` per-vertex (`_disk_shade()` in
`weld_symbol.gd`) and fills via `draw_polygon`'s Gouraud-interpolated vertex
colors — no shader material needed for the fill, and no risk of it also
recoloring the flat hairline-stroke/glow layers drawn in the same `_draw()`
(a real material would apply to every draw call on the node, not just the
fill). `node_visuals_composite.gd._sync_shared()` mirrors ALL of InnerDisk's
shading inputs onto WeldSymbol (`tint_color`, `tint_mix`, `allocated`,
`highlight_position`, `highlight_intensity`), not just `tint_color` — the
design intent is that the weld reads as sunk into the same metal, not an
independently-lit sticker, so drift in any one of those inputs breaks that.

**Gotcha that motivated all this:** an `@tool` script that builds a `Resource`
in `_ready()` and assigns it to an `@export`ed field can get that result baked
as the scene's *default* value by an editor save pass (same family of bug as
the class-cache/editor-mutation gotcha in `godot-workflow.md`). `rim_ring`'s
old CPU-banded design built a `Curve` this way without marking it
`resource_local_to_scene` — the editor baked ONE Curve into `rim_ring.tscn`'s
default, and since a non-local-to-scene default Resource is shared by
reference across every instance of a PackedScene, all 4 stacked rings in the
composite (#126's ring-stacking stake mode) pointed at the same Curve. Any
script that constructs a Resource at runtime and assigns it to an export:
mark it `resource_local_to_scene = true` (if it must stay per-instance) or —
better, per above — hoist it to a shared static and drive variance through
instance uniforms instead.

Performance note for future components in this family: canvas_item fragment
shaders are cheap per-pixel (a skill node is tiny on screen); the real cost to
watch is draw calls, not shader complexity. `rim_ring`'s old approach issued
28 `draw_circle` calls per ring to fake shading via CPU-side banding — a
single shader-drawn ring with a real height-function bumpmap is both cheaper
(1 draw call) and higher quality (continuous, not banded).

## The one formula

Every **stroked ring** is specified as `(inner_offset, width)` relative to the
node's canonical `radius`, and drawn via the single helper:

```gdscript
SkillNode.ring_centerline(node_radius, inner_offset, width)  # → stroke centerline
```

- `inner_offset` — signed gap from `radius` to the ring's **inner edge**
  (negative = inset; the ring lies *inside* the boundary).
- inner edge = `radius + inner_offset`
- outer edge = `radius + inner_offset + width`
- centerline = `radius + inner_offset + width/2` ← what `draw_arc` /
  `draw_circle(..., filled=false, width)` actually take.

**`radius` is never redefined by this.** It stays the load-bearing boundary used
by collision, `edge_point`, `segment_between`, the blade sim (`sn.radius`), fog,
and `edge.gd`. Rings are expressed *relative* to it. Don't fold ring geometry
back into `radius`.

**Filled discs are not rings** — the wash (`radius`) and the inner ownership disk
(`inner_radius`) in `base_circle.gd` are solid `draw_circle(filled=true)` and
don't use the convention.

## Band table (inner → outer; stock `radius=32`, `inner_radius=24`)

| Ring | File | `inner_offset` | `width` | span | sits |
|---|---|---|---|---|---|
| Archetype border | `base_circle.gd` `BORDER_INNER_OFFSET` | `-BORDER_WIDTH` (−8) | 8 | 24..32 | inset; outer edge flush at `radius` |
| Sensed outline | `base_circle.gd` | `-SENSED_OUTLINE_WIDTH/2` (−0.75) | 1.5 | 31.25..32.75 | straddles the boundary (centerline = `radius`) |
| Selection / status | `node_highlight_overlay.gd` `ring_inner_offset` | 4.5 | 3 | 36.5..39.5 | outside the boundary |

The archetype border's inner edge (24) coincides with `inner_radius` only because
`BORDER_WIDTH == radius − inner_radius` at stock sizing — keep that in mind if
either constant moves.

## Hover is a glow, not a ring (#73)

Hover is deliberately a **different visual register** from the stroked rings: a
soft radial **glow halo** (`hover_ring.gd`), not a stroke. It's authored as a
`GradientTexture2D` (FILL_RADIAL) with three control radii, all authored
relative to the node boundary (`radius`). They live in a shared [GlowStyle]
resource (`skill_node/glow_style.gd`, default `default_hover_glow.tres`) — one
`@export var style` on HoverRing whose setter rebinds the resource's `changed`
signal to a texture rebuild. NOTE: a custom resource does NOT auto-emit `changed`
on assignment (verified + per the engine docs), so each `GlowStyle` field carries
a trivial `set(v): field = v; emit_changed()` — the side effect is uniform and in
the *data* object, decoupled from the consumer's rebuild. The knobs:
`inner_feather` (how far inside the peak the fade-in starts) →
`peak_outset` (peak position past the boundary) → `outset` (outer fade-to-0).
Defaults (`feather 2`, `peak +2`, `outset 14`) put the inner edge right at the
boundary so the colored archetype ring keeps its pure type colour. Because it's a
glow rather than a stroke, it layers cleanly *under* the crisp selection/status
ring instead of clashing with it — hover means "pointer is here" (transient),
the ring means "this node has a mechanical role" (state). This is why hover
doesn't need to participate in the `ring_centerline` convention or dodge the
selection band: the two are different registers by design, so they coexist for
free (no `(role) × (hover Y/N)` state explosion).

## Exempt: the range ring

`node_highlight_overlay.gd`'s **range ring** draws AT `range_radius` (centerline),
not via the convention — it's a gameplay reach (world-space radius), not a
decoration band.

## Known follow-up (design, not geometry)

The selection ring (36.5..39.5) overlaps the hover band (32..40), so a node that
is both hovered and selected shows two clashing strokes. Open design question
raised in #67: make hover a radial **glow/fade** rather than a hard ring, and/or
unify hover + selection into one state (while still giving hover feedback when
something is selected). Deferred to a `design`-labelled issue — this rule only
pins the *geometry* convention, not the visual language.
