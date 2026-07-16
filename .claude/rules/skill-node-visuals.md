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
just the always-on legibility wash + the hit-flash/deny tint channel; the
border ring and the allocated inner-disk draw retired in favor of
RimRing/InnerDisk, and the sensed-fog outline moved onto the composite's own
[SensedOutline] component (#141 — see the sensed section below).
Preview all components + the composite together via the sandbox host's
"Node Visuals" tab (`addons/sandbox_host/tabs/15_node_visuals_tab.tscn` →
`skill_node/visuals/panel/node_visuals_panel.tscn`).
`SkillNodeRingVisual.ring_centerline()` delegates to `SkillNode.ring_centerline`
(this file's formula) rather than forking it — keep it that way.

### The identity contract: provided by the base class, consumed freely

`SkillNodeVisual` **provides** four things to every component in the family:
`radius`, `entity_tint`, `archetype_tint`, `allocated`. The composite is the
sole authority on all four and loop-sets them over `_children` in
`_sync_shared()` — it does NOT poke named properties on named children. That
hand-written fan-out is exactly what let RimBonuses' glow dial keep rendering
in entity color for months after rims went archetype-colored: adding a tint
export doesn't fail loudly when nobody wires it, it just silently renders its
default forever.

Children then **consume freely**. A component reads one identity, the other,
both, or neither, and may mix either against a private color of its own:
RimRing blends its bronze `BASE_COLOR` metal toward `archetype_tint` by
`tint_mix`; InnerDisk blends grey toward `entity_tint` by its own `tint_mix`;
CoreHalos reads `entity_tint` and keeps only its `halo_opacity` private. **A
private color is legitimate** — "these rune glyphs are gold regardless" needs
no permission from the base class. What the contract guarantees is only that
both identities are *reachable* and *in sync*, so flipping a component from
one to the other is a one-line edit rather than a re-plumbing.

Never collapse the two tints into one. `entity_tint` says "this is MINE" (the
central disk, the core halos); `archetype_tint` says "this is what I AM" (every
rim, the rune ring) and stays legible whether or not the node is owned.
`allocation_level` (0 = unowned, 1 = baseline, 2+ = staked, capped by
`stake_level`) is the single source of truth for `allocated` — the composite's
`allocation_level` setter derives it; nothing else assigns it.

### One animation clock, on the base class

CoreHalos, RuneRing and RimBonuses each used to carry `var _t`, a `_process`
that accumulated it, a `queue_redraw()`, and a `set_process(cond)` in both a
setter and `_ready`. That's now `SkillNodeVisual.anim_time` +
`set_animating(bool)`. Scale the clock where you read it (`anim_time *
spin_speed`), not where you accumulate it, so turning a speed knob doesn't jump
the phase.

**The trap the base class has to work around:** declaring `_process` on a base
makes Godot auto-enable processing on *every* subclass, static ones included —
and it does so *after* `_enter_tree`, so re-asserting the flag there is too
early. `SkillNodeVisual` therefore hooks `NOTIFICATION_READY` via
`_notification`, not `_ready`: a subclass with its own `_ready` (InnerDisk,
RimRing) would shadow the base's without a `super()` call, while `_notification`
reaches the whole chain. `test_node_visuals_contract.gd` asserts a static disk
and rim are off the process list — it caught this exact bug when the gate was
in `_enter_tree`.

### Identity is loop-set; the light is a shared object. Two flows, on purpose

`LightingStyle` (`lighting_style.gd`, the [GlowStyle] pattern) carries the
faked main light — `highlight_position` / `highlight_intensity` — and nothing
else. InnerDisk is its source of truth; the composite hands the SAME object to
InnerDisk and every RimRing, each connecting once to `changed`, so disk and rim
cannot drift onto two different lights.

That's a different mechanism from identity on purpose, and the difference is
real rather than stylistic: **a light is one shared thing many surfaces
sample** (so: one object, by reference), while **an identity color is a
per-component choice between two provided values** (so: two fields, pushed to
all). Don't force them through one channel. `LightingStyle` used to also carry
`tint_color`/`allocated`/`tint_mix` back when it was called `ShadingStyle`;
those left when the identity contract landed — `tint_mix` in particular is
per-component (the disk's saturation vs. the rim's stake-driven metal blend
share a name and mean different things), so it never belonged in a shared
object.

`shading`/`lighting` stays a plain `var`, deliberately NOT `@export`: it holds
a composite-built resource, and an exported field assigned inside a `@tool`
`_sync_shared()` gets baked into the scene by an editor save (the
Resource-in-`_ready` gotcha below).

**InnerDisk always draws.** Allocation is a color change, not a topology
change: `sn_disk_color()` lights the same dome with the same normal and the
same specular either way, and only swaps which base the light falls on
(`base_tint` when owned, `base_dark` when not). So an unallocated node reads as
a physical hemisphere that is switched OFF — still shiny, just dark — and
allocation animates for free, because it's a lerp between two colors rather
than a pop between two shapes. Don't reintroduce an `InnerDisk.visible =
allocated` gate or an early `return SN_NEUTRAL_DARK` in the shader; both
amputate the lit-dark branch that already exists. BaseCircle's wash is fully
occluded by the disk+rim on a visible node and is hidden outright when `sensed`
(its wash carries the OWNER colour, which must not leak through fog).

### Sensed (#141): a real composite state, not "hide the stack and let a legacy renderer stand in"

`NodeVisualsComposite.sensed` is the archetype-only fog representation. When
true it hides the `ShaderStack` grouping node (the parent of InnerDisk / RimRing
/ RimBonuses / CoreHalos / RuneRing) and shows [SensedOutline] — a **non-shader**
`SkillNodeVisual` that `_draw`s a faint archetype-tinted ring. Two properties are
load-bearing:

1. **Archetype-only is STRUCTURAL, not enforced by `visible=false`.** SensedOutline
   reads only `archetype_tint`, never `entity_tint` — so a sensed node *cannot*
   draw its owner by construction. That's the property the per-viewer info gate
   (next layer up, see `docs/domain/vision-system.md`) is meant to build on.
2. **Zero instance-uniform slots (#172), same gate as fog-hidden.** Hiding the
   `ShaderStack` — not each child — flips every shader child's
   `is_visible_in_tree()` false in one move, while CoreHalos/RuneRing keep their
   own default-hidden `visible` flags. `_apply_sensed()` resolves ShaderStack by
   **direct child path**, NOT a `%`-unique-name `@onready`, so the `sensed` setter
   works before the node enters the tree: `instantiate()` then `sensed = true`
   hides the stack *before* the shader children's `_ready` runs, so they never
   bind a material. A `%`-name returns null until in-tree, which would leave the
   stack visible through the children's `_ready` and claim a slot. `SkillNode`
   also hides `BaseCircle` when sensed (owner-coloured wash). Guarded by
   `test_node_visuals_contract.gd`'s `*_sensed_*` tests.

### RimBonuses' stake-fill dial (#127) is the stake visualization

Its current/max glow dial (`fill_current`/`fill_max`, synced from
`allocation_level`/`stake_level`) is archetype-tinted like every other rim
element — it reads the inherited `archetype_tint` through `_tone_color()`, the
same as the RimTone gems, and owns no tint export of its own. RimHolder is the
one exempt layer: it stays neutral chrome regardless of tint or allocation.

**This is the sole stake/cap depth visualization since #172.** There used to be
a second approach — ring-stacking (`rim_growth` grew RimRing2/3/4 outward per
stake level) — but those extra rings were `visible = false` placeholders on
*every* node, and each still cost a shared-instance-uniform-buffer slot (see the
buffer section below). At 2000+ nodes/level that per-node tax wasn't worth a
rarely-used alternate look, so RimRing2-4 + `rim_growth`/`ring_gap` + the
`StakeLabel` were removed and RimBonuses is now the only stake read. Growing the
node's actual `radius` with stake (it's already wired through collision/fog/reach)
is a possible visual follow-up (#178). `0/*` draws nothing at all (no backdrop either); `M/N` with
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
`weld_sides` (via `arch`)/`well_depth` `instance uniform`s on
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

**Two things keep this cheap, and BOTH are load-bearing (#172):**

1. **The scene must NOT bake `material` or `instance_shader_parameters/*`.** Each
   CanvasItem that has an instance-uniform material bound (or any instance param
   set) claims a slot in the *shared global* instance-uniform buffer — allocated
   at load, and independent of whether the item is visible. Because these are
   `@tool` scripts, an editor save serializes the live-preview `material =
   SubResource(...)` + a full `instance_shader_parameters/*` block into the
   scene (same round-trip family as `godot-workflow.md`'s "editor mutates
   scenes"). That bakes a slot onto *every* instance — fog-hidden nodes, the
   invisible procgen Node-Graph-preview graph, all of it — and the software
   rasterizer's cap is only 4096 items ("Too many instances using shader
   instance variables"). `SkillNodeVisual._validate_property()` clears
   `PROPERTY_USAGE_STORAGE` on `material` and any `instance_shader_parameters/*`
   so the script still sets them live but the editor can never re-bake them.
   **Don't re-add a `material =` line to `inner_disk.tscn`/`rim_ring.tscn`** —
   the script owns the shared static material; a scene-baked one isn't even the
   shared instance (it breaks batching *and* costs the slot).

2. **`_sync_material()` gates on `is_visible_in_tree()`** and binds the material
   only past that gate, with a `visibility_changed` re-sync to set the uniforms
   the frame the node is shown. So a node whose whole composite is hidden claims
   zero slots — that covers **sensed-fog** nodes (`NodeVisualsComposite.sensed`
   hides the `ShaderStack`, see the sensed section above) and every node on the
   procgen Node-Graph-preview's invisible graph (the measured win).
   `is_visible_in_tree()` (not local `visible`) is deliberate — it's what makes a
   whole hidden stack free, not just a locally-hidden child. Guarded by
   `test_node_visuals_contract.gd` (`*_ship_no_baked_material`,
   `*_fog_hidden_*`, `*_unfogged_*`, `*_sensed_*`).

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

There is **no hairline**. An additive `hairline_width`/`hairline_opacity`
stroke tracing the glyph's boundary was tried and removed — the height-field
dent already reads as an edge, so the stroke only fought the sunk-in look. It
had been disabled (`hairline_opacity = 0.0`) and commented out of the shader
long before the exports came out; don't re-add it without a reason the dent
can't serve. Glow/pulse/sweep FX (the old `GlowMode` enum) were dropped too — an
outward glow on hover fought the sunk-in read and was never the right call;
a *full-shape* glow/bloom is a possible follow-up for more elaborate emblems
(a lit sword, a shimmering dragon) but isn't part of this small gem-indent
look.

**How the light is delivered: the shared `LightingStyle` resource** — see "two
flows" above. Each consumer connects ONCE to `changed` and copies the fields in
(`_apply_lighting()`); RimRing reads only `highlight_position` → its
`light_dir`. A null `lighting` (standalone preview) falls back to the child's
own `@export`s. Both flows are guarded by
`test/unit/test_node_visuals_contract.gd`, whose identity test walks EVERY
`SkillNodeVisual` descendant rather than a hand-listed few — that's the
assertion that would have caught the dial.

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

### The diamond crown (loot relic, #168): a precomputed LUT, not per-pixel facet math — because every instance is IDENTICAL

`InnerDisk.show_diamond` (the `SkillDustAddon` relic's gem-cut glyph) is a
second height-field glyph alongside the weld, but built differently on
purpose. The weld's shape varies per node (different archetype → different
`weld_sides`/`weld_k`), so it has to stay an analytic per-pixel formula
(`sn_polygon_facet`/`sn_bowl_drop`). The diamond crown is the SAME shape on
every relic — no per-instance parameter varies it — so recomputing its
`atan2`/`mod`/facet math per pixel, per instance, every frame, buys nothing.
Instead `InnerDisk._build_diamond_lut()` (lazy `static var _diamond_lut`,
same caching shape as `_shared_material`) bakes a small texture (table
flat-depth region + 8 linear-ramp crown facets, computed with a GDScript
twin of the facet math — see below for why that's fine here) ONCE, and
`sn_diamond_bump()` (`lighting.gdshaderinc`) just decodes it per pixel.

**Why the LUT doesn't break batching, when the rule elsewhere says samplers
force `resource_local_to_scene`:** that constraint is specifically about a
sampler that VARIES per instance (rim_ring's custom-curve escape hatch). This
LUT is identical for every `InnerDisk`, so it's bound as a plain
`uniform sampler2D diamond_lut` (NOT `instance uniform`) on the one shared
`ShaderMaterial`, set once in `_ready()` — every instance samples the same
texture object, same as every instance already shares the one
`ShaderMaterial` itself. Only a per-instance-varying sampler would force the
duplicate-material path.

**Why the GDScript bake isn't the "CPU twin of the shading formula"
anti-pattern the weld glyph retired** (`weld_symbol.gd`'s old
`_disk_shade()`, warned about above): that anti-pattern was two independently
*maintained* implementations of the same formula drifting apart over time.
Here there is only ONE implementation — the GDScript bake — and the shader
never re-derives the geometry, only decodes the baked texel. There's nothing
for it to drift from.

Encoding: R = `drop / DIAMOND_DEPTH` (0..1), GB = `grad / DIAMOND_GRAD_SCALE`
remapped -1..1 → 0..1, A = 1 inside the girdle else 0 (cheap "skip the bump"
gate, and keeps bilinear sampling from bleeding a dark ring across the
boundary). The bake constants in `inner_disk.gd` and the decode constants in
`lighting.gdshaderinc` (`SN_DIAMOND_DEPTH_SCALE`/`SN_DIAMOND_GRAD_SCALE`)
must stay numerically in lock-step — they're two halves of one encoding, not
independently tunable.

**When to reach for this vs. the weld's per-pixel formula:** if a future
glyph needs per-instance variation (different archetype, different sides,
different depth), it has to be the analytic per-pixel path like the weld —
a LUT can't vary per instance without becoming a per-instance sampler (the
exact escape hatch this section says the LUT avoids). Reach for a baked LUT
only when the shape truly is fixed across every instance that shows it.

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
