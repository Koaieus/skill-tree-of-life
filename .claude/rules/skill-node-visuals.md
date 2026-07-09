---
description: SkillNode visuals
paths:
  - "skill_node/visuals/**"
---
# SkillNode visuals — ring band convention (#67)

How the concentric rings around a `SkillNode` are sized. One convention, one
formula, so radii stay legible "going forward" instead of each ring re-deriving
its own.

## SkillNode-visuals-v2 (milestone #16) — cut over; SkillNode composes it

`skill_node/visuals/` holds the component family (`SkillNodeVisual` /
`SkillNodeRingVisual` base classes in that same directory, plus `inner_disk`
(whose weld glyph is a height-field dent in its own shader — see below), `rim_ring`,
`rim_bonuses`, `core_halos`, `rune_ring`, `node_visuals_composite`)
implementing the 6 locked-pick visuals from
`docs/design/handoff_skill_nodes_visuals/Handoff Prep.dc.html`.
`SkillNode` (`skill_node.tscn`) instances `node_visuals_composite.tscn` as
`%NodeVisualsComposite` and `_sync_visuals()` is what actually drives it —
this **is** the live disk/rim render, not a parallel preview. `base_circle.gd`
/ `hover_ring.gd` / `core_marker.gd` stay, but `base_circle.gd` was slimmed to
just the always-on legibility wash + the sensed-fog outline; the border ring
and the allocated inner-disk draw retired in favor of RimRing/InnerDisk.
Preview all components + the composite together via the sandbox host's
"Node Visuals" tab (`addons/sandbox_host/tabs/15_node_visuals_tab.tscn` →
`skill_node/visuals/panel/node_visuals_panel.tscn`).
`SkillNodeRingVisual.ring_centerline()` delegates to `SkillNode.ring_centerline`
(this file's formula) rather than forking it — keep it that way.

### Two tints, two jobs (`node_visuals_composite.gd`)

`entity_tint` (the allocating entity's/"player's" color) and `archetype_tint`
(the node's persistent type identity, `SkillNode.base_type_color`) are
separate exports — never collapse them back into one `tint_color`.
`entity_tint` drives InnerDisk (weld glyph included) and CoreHalos —
things that read as "this is MINE". `archetype_tint` drives RimRing's
`tint_mix` (mixed toward the ring's own bronze/gold metal at low mix),
RuneRing, and RimBonuses — structural reads that stay legible whether or not
the node is owned. `allocation_level` (0 = unowned, 1 = baseline, 2+ = staked,
capped by `stake_level`) is the single source of truth for `allocated`
(`allocation_level > 0`, a getter — never set directly); InnerDisk hides
entirely when unallocated rather than showing a dimmed disk, and BaseCircle's
wash is what carries the unallocated node's footprint instead.

### RimBonuses' stake-fill dial (#127 follow-up) is a second, independent stake visualization

Its current/max glow dial (`fill_current`/`fill_max`, synced from
`allocation_level`/`stake_level`) is archetype-tinted like every other rim
element — it reads through RimBonuses' single `tone_tint`, no second tint
export. This is approach B for stake/cap depth, alongside approach A (ring-stacking,
`rim_growth`) — both wired off the same `allocation_level`/`stake_level`,
picked per-node by toggling which one is `visible` (default: RimBonuses stays
`visible = false` in `node_visuals_composite.tscn`, approach A is the
default look). `0/*` draws nothing at all (no backdrop either); `M/N` with
`N > 1` divides the circle into `N` **evenly-gapped** slots (gap size an
export, applied uniformly whether a slot is filled or not, so a partial fill
still reads as evenly spaced) and lights the first `M`; `M == N == 1` is a
special case — a single full ring with zero gap, not a 1-slot dial (a 1-slot
dial would just be "almost a full circle minus one gap", which isn't the same
read as "fully lit"). The glow itself is faked via 3 stacked
`draw_arc`/`draw_circle` strokes at shrinking width + rising alpha (same CPU
technique as `core_halos.gd`/`rune_ring.gd`'s `edge_glow`) rather than a
shader — there's no project-wide glow/bloom `WorldEnvironment` to justify one,
and the layered-stroke fake reads convincingly at this node's on-screen size.

### The weld glyph is folded straight into InnerDisk's own shader — not a composite sibling, not even a sibling node

There is no `WeldSymbol` node anymore. The glyph is `show_weld`/`weld_k`/
`weld_sides` (via `arch`)/`well_depth`/`hairline_*` `instance uniform`s on
`inner_disk.gdshader` itself, set from `@export`s on `inner_disk.gd` in the
same `_sync_material()` pass as the dome's own tint/highlight uniforms. The
composite only ever talks to `%InnerDisk`; there's nothing else to keep in
sync. See "Weld: a regular-polygon bowl dent in the dome's own height field"
below for the geometry.

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

**Shared lighting math lives in `lighting.gdshaderinc`** (`#include`d by both
`inner_disk.gdshader` and `rim_ring.gdshader`). The faked main-light direction
(`sn_light_dir` — `normalize(vec3(dir_xy, SN_LIGHT_Z=0.65))`), Lambert
(`sn_diffuse`), specular (`sn_specular`), the dome normal (`sn_dome_normal`), and
the full disk color (`sn_disk_color`) are defined once there, so the disk and its
rim can't drift onto two different light models. The weld glyph's math
(`sn_polygon_facet`/`sn_bowl_drop`, see below) lives there too now — the CPU
twin this section used to warn about (`weld_symbol.gd`'s `_disk_shade()`) is
gone; the glyph is lit by the exact same `sn_disk_color` call as the dome, fed
a different normal, so it cannot drift from it by construction.

`rim_ring` carries NO knowledge of the disk beneath it — it only owns its own
`inner_radius`/`outer_radius` band (base class) plus an interior `crest_r`
control point marking where the flat floor ends and the bevel to the rim
begins. `node_visuals_composite.gd` is the one layer that knows both InnerDisk
and RimRing exist; it lines `RimRing.inner_radius` up with `InnerDisk.disk_radius`
so the two abut, rather than RimRing reaching for disk-shaped exports itself.

### Weld: a regular-polygon bowl dent in the dome's own height field

Earlier versions faked the glyph with a CPU twin of the disk's shading
formula (flat-shaded via `draw_polygon`'s Gouraud vertex colors, a separately
inset "floor" polygon, an AO tint on the exposed wall, a hardcoded glow/sweep
overlay). All of that is gone — the glyph is now a **real height-field dent**
carved into `inner_disk.gdshader`'s own dome, lit by the exact same
`sn_disk_color`/`sn_diffuse`/`sn_specular` call as the rest of the disk (see
`sn_polygon_facet`/`sn_bowl_drop` in `lighting.gdshaderinc`).

**Profile: a bowl, not a stamped pit.** Depth is 0 at the glyph's own
boundary and ramps up to the full `well_depth` export at the glyph's own
visual center — literally the SAME `sqrt(1-t²)` dome shape the main disk
uses, just re-centered/rescaled to the glyph's local footprint (a mini
inverted dome nested in the big one, not a new shape to invent).

**Regular polygons only, decomposed into `weld_sides` flat facets** (the
`arch`/`ARCH_SIDES` sides-per-archetype placeholder mapping is unchanged —
still not wired to the node's real archetype, a pre-existing gap). Each
facet's gradient is a CONSTANT vector — that flatness is deliberate, it's
what reads as crease "depth lines toward the visual center" rather than a
smooth continuous bowl. **Arbitrary glyphs (rune/kanji) are explicitly
deferred**: passing an arbitrary polygon per-instance would need a
per-instance LUT texture (baked SDF or vertex data), which forces the
`resource_local_to_scene` duplicate-material escape hatch documented above
(samplers can't be `instance uniform`s) — breaking every InnerDisk's shared
single-draw-call batching for a feature not yet used. Regular polygons stay
on the analytic-SDF path and keep batching intact.

**Normal: analytic gradient, not screen-space derivatives.** The combined
height is `H(p) = z_dome(p) - drop(p)`; its gradient is computed in closed
form (`∇z_dome = -p/z_dome`, `∇drop` from the bowl's own chain rule) and fed
through `normalize(vec3(-∇H, 1))` — NOT `dFdx`/`dFdy`. Screen-space
derivatives alias badly at this node's on-screen size (~48-64px, computed
per 2×2 pixel quad) and specifically misbehave at the facet crease lines,
which is exactly the feature. **Backward-compat proof**: when `well_depth`
is 0 or `p` is outside the glyph, `∇drop = 0`, so `∇H = ∇z_dome`, and
`normalize(vec3(-∇z_dome, 1))` reduces algebraically to the existing
`sn_dome_normal(p)` (scaling by `1/z_dome` doesn't change a normalized
direction) — so `show_weld = false` (or any pixel outside the glyph) renders
byte-identical to the plain dome; the shader only branches into the new path
when the sampled point is actually inside the bowl (`bowl.x > 0.0`).

A hairline (`hairline_width`/`hairline_opacity`, now expressed as a fraction
of the disk radius rather than a pixel width) traces the glyph's true
boundary as a thin additive brightening, independent of the height field.
Glow/pulse/sweep FX (the old `GlowMode` enum) were dropped entirely — an
outward glow on hover fought the sunk-in read and was never the right call;
a *full-shape* glow/bloom is a possible follow-up for more elaborate emblems
(a lit sword, a shimmering dragon) but isn't part of this small gem-indent
look.

**How those five are delivered: a shared `ShadingStyle` resource, NOT imperative
mirroring.** `node_visuals_composite.gd` holds ONE `ShadingStyle`
(`skill_node/visuals/shading_style.gd`, a Resource — the [GlowStyle] pattern) and
assigns it to InnerDisk (weld glyph included, since it's the same node/material
now) and every RimRing via their `shading` var.
That var is a **plain `var`, deliberately NOT `@export`** — it holds a
composite-built runtime resource, and an exported field assigned inside a @tool
`_sync_shared()` gets baked into the scene by an editor save (the same
Resource-in-`_ready` gotcha this file documents below). Each consumer connects
ONCE to `changed` and copies the fields in
(`_apply_shading()`); RimRing reads only `highlight_position` → its `light_dir`
(its band color is stake-driven). `_sync_shared()` therefore edits the one object
instead of poking five props per child — adding a new shaded consumer is one
`child.shading = _shading` line, and a single source object makes drift
impossible. A null `shading` (standalone preview) falls back to the child's own
`@export`s. Guarded by `test/unit/test_node_visuals_shading.gd`.

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
