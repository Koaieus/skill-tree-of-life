# SkillNode visuals — the component family

How a `SkillNode` is drawn: the shader-stack components, the identity contract
they share, the carve glyph in InnerDisk, and the ring band convention. The
central emblem (CARVE / BLOOM registers, priority ladder) is
[skillnode-emblem.md](skillnode-emblem.md); the offline LUT bake is
[emblem-bake.md](emblem-bake.md); the 3D core look is [gimbal-3d.md](gimbal-3d.md).
The gotchas an editing agent must not trip over are in
`.claude/rules/skill-node-visuals.md`.

## Components

`skill_node/visuals/` holds the family. `SkillNodeVisual` and
`SkillNodeRingVisual` (`ring_visual.gd`) are the base classes; the rest are leaf
scripts that deliberately declare no `class_name` (a test `preload`s the script to
reach their enums).

| Component | Role |
|---|---|
| `inner_disk` | the dome, opaque across its whole band; hosts the carve glyph in its own shader |
| `rim_ring` | the beveled rim: archetype tint, height presets, stake-fill dial |
| `core_presence` | the core's slot: an empty `Slot` for the owner's look plus `CoreSigilBloom` |
| `core_gimbal` / `core_halos` | core looks (3D rig / 2D rotate-once layers) |
| `sensed_outline` | non-shader archetype-only fog representation |
| `node_visuals_composite` | the one layer that knows its children; owns identity fan-out, carve routing, stake dial |
| `rim_bonuses` / `rune_ring` | not in the composite; instanced only in the sandbox "Node Visuals" tab |

`SkillNode` (`skill_node.tscn`) instances `node_visuals_composite.tscn` as
`%NodeVisualsComposite`; `_sync_visuals()` drives it. Preview every component and
the composite in the sandbox host's "Node Visuals" tab
(`addons/sandbox_host/tabs/15_node_visuals_tab.tscn` ->
`skill_node/visuals/panel/node_visuals_panel.tscn`). `hover_ring.gd` draws the
hover glow; InnerDisk and RimRing draw opaquely across their whole band whatever
the allocation, so there is no separate legibility wash. The `ShaderStack` node
groups InnerDisk, RimRing and CorePresence.
`SkillNodeRingVisual.ring_centerline()` delegates to `SkillNode.ring_centerline`
rather than forking the formula.

### rim_bonuses and rune_ring: off the composite

They are alternate looks, not simultaneous layers, and crowd each other. Their
scenes and scripts stay in the repo and in the Node Visuals tab (that preview is
the shelf); nothing is left hidden-but-instanced, because a level carries
500-2500 SkillNodes and an unused child costs tree nodes, `_ready` work and
potentially an instance-uniform slot on every one
(`rendering-performance.md`). Re-adding one is instancing its scene under
`ShaderStack`.

## Identity contract

`SkillNodeVisual` provides `radius`, `entity_tint`, `archetype_tint`, `allocated`
(plus `owner_level` and `node_seed`) to every component. The composite is the sole
authority and loop-sets them over `_children` in `_sync_shared()`; it never pokes
named properties on named children, because a hand-written fan-out is what leaves
a newly added tint export silently rendering its default.

Children consume freely: one identity, the other, both, or neither, mixed against
a private colour of their own. RimRing blends its bronze `BASE_COLOR` toward
`archetype_tint` by `tint_mix`; InnerDisk blends grey toward `entity_tint` by its
own `tint_mix`; CoreHalos reads `entity_tint` and keeps only `halo_opacity`
private. The contract guarantees both identities are reachable and in sync, so
switching a component from one to the other is a one-line edit.

`entity_tint` says "this is MINE" (the disk, the core look); `archetype_tint` says
"this is what I AM" (every rim) and stays legible whether or not the node is
owned. `allocation_level` (0 unowned, 1 baseline, 2+ staked, capped by
`stake_level`) is the single source of `allocated`: the composite's
`allocation_level` setter derives it and nothing else assigns it.
`test_node_visuals_contract.gd`'s identity test walks every `SkillNodeVisual`
descendant, not a hand-listed few.

## Animation clock

`SkillNodeVisual.anim_time` plus `set_animating(bool)` is the one clock: a
component calls `set_animating(true)` and reads `anim_time` in `_draw()`, scaling
it where it reads (`anim_time * spin_speed`) so a speed knob never jumps the
phase. Declaring `_process` on a base auto-enables processing on every subclass
after `_enter_tree`, so the base gates in `NOTIFICATION_READY` via
`_notification` (reaches the whole chain even when a subclass has its own
`_ready`). `test_node_visuals_contract.gd` asserts a static disk and rim are off
the process list; its positive control drives a standalone `rune_ring.tscn`
(keep one, since `assert_false` alone cannot tell "gated" from "clock broken").

## Core presence

`CorePresence` (`core_presence.tscn`) is a container: an empty `Slot` plus
`CoreSigilBloom`. `SkillNode._refresh_core_presence` pushes the owner's
`CoreClass.core_look` (a `PackedScene`, null off-core) through
`NodeVisualsComposite.set_core_look` -> `CorePresence.set_look`; the same resource
is a no-op, anything else frees the old look and instances the new one with
identity already pushed. `CorePresence` lives under `ShaderStack`, so a sensed
node hides it with no separate gate, and it is in the composite's identity fan-out.

- **Slot contract** = the `SkillNodeVisual` identity (radius, both tints,
  `allocated`, `owner_level`, `node_seed`) + an optional `revealed` + the
  duck-typed travel hooks `on_core_travel_start(local_offset, duration)` /
  `on_core_travel_arrived()`. `CorePresence` re-pushes identity into the look and
  never names a ring, style or phase; a look derives its own params.
- **Looks** (leaf scenes, no `class_name`): `core_gimbal.tscn` is the entity look,
  one `Gimbal3D` rig in the viewport's `GimbalWorld` ([gimbal-3d.md](gimbal-3d.md));
  `core_gear.tscn` is `core_halos.tscn` pinned at COG, the Dormant Core's look via
  `blocker_core.tres`. A boss is an inherited `core_gimbal` with `style` pinned.
  `CoreHalos` keeps only rotate-once styles `{NONE, RINGS, ORBIT, COG}`.
- **Travel.** On a core move the composite tweens `CorePresence`'s local
  `position` from the old node's relative offset to zero (`glide_core_presence`);
  the bloom extinguishes and reignites, the look glides. The core-move drag ghost
  (`core_drag_ghost.tscn`) instances the same scene with a `modulate`-alpha copy at
  the hovered target.
- **A rig lives outside the ShaderStack.** `process_mode` does not cross into the
  GimbalWorld, so `CoreGimbal` gates on `is_visible_in_tree()` (visibility does
  propagate its notification) and mirrors it onto the rig's `visible`.

## Lighting: identity is loop-set, the light is a shared object

`LightingStyle` (`lighting_style.gd`, the `GlowStyle` pattern) carries the faked
main light (`highlight_position`, `highlight_intensity`) and nothing else.
InnerDisk is its source of truth; the composite hands the SAME object to InnerDisk
and every RimRing, each connecting once to `changed` (`_apply_lighting()`), so disk
and rim cannot drift onto two lights. RimRing reads only `highlight_position` as its
`light_dir`; a null `lighting` (standalone preview) falls back to the child's own
`@export`s.

The two flows differ on purpose: a light is one thing many surfaces sample (one
object by reference), an identity colour is a per-component choice between two
provided values (two fields pushed to all). `tint_mix` stays per-component: the
disk's saturation and the rim's stake-driven metal blend share a name and mean
different things. The `lighting` field is a plain `var`, not `@export`: it holds a
composite-built resource (see the Resource-in-`_ready` gotcha in the rule).

## InnerDisk always draws

Allocation is a colour change, not a topology change. `sn_disk_color()` lights the
same dome with the same normal and specular either way and swaps only the base
(`base_tint` owned, `base_dark` not), so an unallocated node is a hemisphere that
is switched off, and allocation animates as a lerp between two colours. There is
no `InnerDisk.visible = allocated` gate and no early `return SN_NEUTRAL_DARK`.

## Sensed

`NodeVisualsComposite.sensed` is the archetype-only fog representation. When true
it hides the `ShaderStack` and shows `SensedOutline`, a non-shader
`SkillNodeVisual` that `_draw`s a faint archetype-tinted ring.

1. **Archetype-only is structural.** SensedOutline reads only `archetype_tint`,
   never `entity_tint`, so a sensed node cannot draw its owner. The per-viewer info
   gate (`vision-system.md`) builds on that.
2. **Zero instance-uniform slots, same gate as fog-hidden.** Hiding the
   `ShaderStack` flips every shader child's `is_visible_in_tree()` false in one
   move. `_apply_sensed()` resolves the stack by direct child path, not a `%`-name
   `@onready`, so the setter works before the node enters the tree:
   `instantiate()` then `sensed = true` hides the stack before the children's
   `_ready` runs and they never bind a material. Guarded by
   `test_node_visuals_contract.gd`'s `*_sensed_*` tests.

## RimRing stake dial

`fill_current` / `fill_max` are forwarded from the composite's `allocation_level`
/ `stake_level` in `_sync_stake()` and folded into `rim_ring.gdshader` as an
additive term; RimRing draws the dial itself, no separate CanvasItem.
`SkillNode.radius` also grows with `stake_level` (`stake_radius_delta`), so size
and the 1/3-vs-3/3 read are separate channels.

- `0/*` draws nothing, not even an unlit slot outline. `M/N` with `N > 1` divides
  the circle into `N` evenly gapped slots (the gap is a global shared uniform,
  applied whether a slot is lit or not) and lights `M` of them. `1/1` is a single
  full ring with zero gap; only it is gapless.
- The lit term is additive across the whole `inner_r`..`outer_r` band, strongest
  at the crest, stacked on the `tint_mix` archetype swing.
- **Static.** No `TIME` in the shader and no `_process` clock on RimRing.
- **Anchored at 12 o'clock, bilaterally symmetric.** Slot 0 is centred at top;
  every state is left/right symmetric for every `M` (top/bottom asymmetry is
  accepted). An odd `M` needs a preference order over the self-mirrored slots,
  since a single nested "add the next symmetric unit" path skips some `M`
  (worked derivation: `rim_fill_lit()` in `rim_ring.gdshader`).

## The carve glyph lives in InnerDisk's shader

There is no separate glyph node. The glyph is the `carve_kind` / `carve_sides` /
`carve_squish` / `carve_radius` / `well_depth` / slice `instance uniform`s on
`inner_disk.gdshader`, pushed in the same `_sync_material()` pass as the dome's
tint and highlight; the composite talks only to `%InnerDisk`.
`InnerDisk.CarveKind` is `{NONE, POLYGON, GEM, TEXTURE}`: the shader's int branch
selector, mapped from the shape's type by InnerDisk (`skill_node/visuals/emblem/`
knows nothing of InnerDisk).

**Authored vs. effective.** InnerDisk carries no scalar carve knobs. The authored
state is `carve_shape: CarveShape` (a shared `emblem/shapes/*.tres` or any authored
shape; `null` is the empty dome) plus the `well_depth` style dial. The other entry
is `set_carve()`, which stores the RESOLVED shape and writes nothing exported.
`_sync_material()` pushes the getter-only `effective_carve_*` /
`effective_well_depth` derivations (the resolved shape when one has arrived, the
authored `carve_shape` otherwise); `carve_params()` packages them as one value.
`NodeVisualsComposite.carve_shape` is the designer-facing knob and routes into the
disk's authored slot; the resolver's `set_carve` outranks it via `_has_carve`
("resolved to nothing" is an honest empty dome, not a fallback). Polygon geometry
(`sides` / `squish_x` / `radius` / `well_depth`) lives on `PolygonCarveShape`,
not the `CarveShape` base: only the polygon path reads it.

`PolygonCarveShape.well_depth` is NEGATIVE to mean "inherit", resolved on the CPU in
`effective_well_depth`; the uniform is `hint_range(0.0, 1.0)`, so a negative that
reached the shader would clamp to `0.0` ("no dent"). A deliberate `0.0` is distinct.

### Polygon carve geometry

The glyph is a real height-field dent in the dome, lit by the same
`sn_disk_color` / `sn_diffuse` / `sn_specular` call as the rest of the disk
(`sn_polygon_facet`, `sn_bowl_drop` in `lighting.gdshaderinc`), so it cannot drift
from the dome's lighting.

- **Profile: a bowl.** Depth is 0 at the glyph boundary and ramps to the full
  `well_depth` at its visual centre: the same `sqrt(1 - t^2)` dome shape,
  re-centred and rescaled to the glyph footprint.
- **Regular polygons, `carve_sides` flat facets.** The side count comes from the
  archetype's `carve_shape` `.tres` in `skill_node/visuals/emblem/shapes/`. Each
  facet's gradient is constant, which reads as crease lines toward the centre.
  Arbitrary glyphs are not analytic: they ride the baked LUT path (gem,
  texture), because per-instance geometry would need a per-instance sampler.
- **Normal: analytic gradient, not `dFdx`/`dFdy`.** With `H(p) = z_dome(p) -
  drop(p)`, the gradient is closed-form (`grad z_dome = -p / z_dome`, `grad drop`
  from the bowl's chain rule) and the normal is `normalize(vec3(-grad H, 1))`.
  Screen-space derivatives alias at this node's ~48-64 px size (per 2x2 quad) and
  misbehave exactly at the creases. Where `well_depth` is 0 or `p` is outside the
  glyph, `grad drop = 0` and this reduces algebraically to `sn_dome_normal(p)`, so
  `CarveKind.NONE` and every pixel outside the glyph render byte-identical to the
  plain dome; the shader branches into the bowl only where `bowl.x > 0.0`.
- **No hairline and no glow/pulse/sweep mode.** The dent already reads as an edge,
  and an outward glow fights the sunk-in read.

## Shared material and instance uniforms

`inner_disk` and `rim_ring` (on its built-in presets) each use ONE shared
`ShaderMaterial`, built lazily in a `static var`, varying per node through
`instance uniform`s and `CanvasItem.set_instance_shader_parameter()`. Every node on
screen then batches into one draw call. Prefer this over a
`resource_local_to_scene` material whenever every varying value is a scalar,
vector or colour; a per-instance-varying sampler is the one thing that forces the
duplicate-material escape hatch (RimRing's custom-Curve fallback, gated on
`_use_custom_curve`).

- **No production rim uses the CUSTOM curve.** The shipped composite uses
  `HeightPreset.MESA`, a closed-form preset in `rim_ring.gdshader` pinned by
  `test_rim_ring_height_presets.gd`. A new rim profile is a new preset function
  appended after `CUSTOM` (index 4: scenes and the shader's LUT branch key on it).
- **Instance-uniform slots are the budget.** Every CanvasItem with an
  instance-uniform material bound claims a slot in the shared global buffer,
  allocated at load whether or not it is visible; the software rasterizer caps at
  4096 ("Too many instances using shader instance variables").
  `SkillNodeVisual._validate_property()` clears `PROPERTY_USAGE_STORAGE` on
  `material` and `instance_shader_parameters/*` so an editor save never bakes
  them, and `_sync_material()` binds the material only past an
  `is_visible_in_tree()` gate, re-syncing on `visibility_changed`. A fog-hidden,
  sensed or Node-Graph-preview node claims zero slots. Guarded by
  `test_node_visuals_contract.gd` (`*_ship_no_baked_material`, `*_fog_hidden_*`,
  `*_unfogged_*`, `*_sensed_*`).
- `rim_ring` knows nothing of the disk beneath it: it owns its `inner_radius` /
  `outer_radius` band plus an interior `crest_r` where the flat floor ends and the
  bevel begins. The composite lines `RimRing.inner_radius` up with
  `InnerDisk.disk_radius` so they abut.
- Fragment shaders are cheap at this node size; draw calls are the cost to watch.

### lighting.gdshaderinc

`#include`d by `inner_disk.gdshader` and `rim_ring.gdshader`. It defines once the
faked light direction (`sn_light_dir`: `normalize(vec3(dir_xy, SN_LIGHT_Z = 0.65))`),
Lambert (`sn_diffuse`), specular (`sn_specular`), the dome normal
(`sn_dome_normal`), the full disk colour (`sn_disk_color`), the polygon carve
(`sn_polygon_facet`, `sn_bowl_drop`) and the LUT decoders (`sn_gem_bump`,
`sn_texture_bump`). Disk and rim cannot sit on two light models.

## Ring band convention

Every stroked ring is `(inner_offset, width)` relative to the node's canonical
`radius`, drawn through one helper:

```gdscript
SkillNode.ring_centerline(node_radius, inner_offset, width)  # -> stroke centerline
```

- `inner_offset` is the signed gap from `radius` to the ring's inner edge
  (negative = inset).
- inner edge = `radius + inner_offset`; outer edge = that + `width`; centerline =
  `radius + inner_offset + width / 2`, which is what `draw_arc` /
  `draw_circle(..., filled=false, width)` take.

`radius` is never redefined by this: it stays the boundary for collision,
`edge_point`, `segment_between`, the blade sim, fog and `edge.gd`. Filled discs
(InnerDisk's dome) are not rings and skip the convention.

Stock `radius = 32`, `inner_radius = 24`:

| Ring | File (export) | `inner_offset` | `width` | span |
|---|---|---|---|---|
| Selection / status (plain role ring) | `ui/indicator/plain_ring.gd` `ring_inner_offset` / `ring_width` | 4.5 | 3 | 36.5..39.5 |
| Target reticle ring | `ui/indicator/target_reticle.gd` `ring_inner_offset` / `ring_width` | 9 | 4 | 41..45 |
| Target reticle arms | `ui/indicator/target_reticle.gd` `arm_inner_offset` / `arm_length`, drawn by `crosshair_arms.gd` | 15 | 8 (length) | 47..55 |

`hilt_marker.gd`, `pulse_ring_marker.gd` and `squad_marker.gd` carry the same
`ring_inner_offset = 9` / `ring_width = 4` defaults as the reticle ring. The
overlay picks the indicator by `IndicatorTheme`.

## Hover is a glow, not a ring

`hover_ring.gd` draws a soft radial glow halo, a different register from the
stroked rings: a `GradientTexture2D` (FILL_RADIAL) with three control radii, all
relative to the node boundary, held in a shared `GlowStyle` resource
(`skill_node/glow_style.gd`). `HoverRing`'s one `@export var style` setter rebinds
the resource's `changed` signal to a texture rebuild. A custom Resource does not
auto-emit `changed` on assignment, so each `GlowStyle` field carries
`set(v): field = v; emit_changed()`; the side effect lives in the data object,
decoupled from the consumer's rebuild.

- `inner_feather` (how far inside the peak the fade-in starts) -> `peak_outset`
  (peak past the boundary) -> `outset` (fade to 0). Script defaults are 2 / +2 /
  14; the shipped `default_hover_glow.tres` sets 7 / +10 / 12.
- It layers under the crisp selection/status ring: hover means "pointer is here"
  (transient), the ring means "this node has a mechanical role" (state). Hover
  therefore skips the `ring_centerline` convention, and there is no
  `(role) x (hover)` state explosion. The plain role ring (36.5..39.5) sits
  inside the hover glow; the two coexist by design.

## Exempt: the range ring

`node_highlight_overlay.gd`'s range ring draws AT `range_radius` (centerline), not
through the convention: it is a gameplay reach in world space, not a decoration
band.
