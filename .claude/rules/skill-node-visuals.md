---
description: SkillNode visuals
paths:
  - "skill_node/visuals/**"
---
# SkillNode visuals — ring band convention (#67)

> The **central emblem** (CARVE / BLOOM registers, priority ladder, the
> contribute→resolve architecture that keeps SkillNode ignorant of
> loot/spell/keystone sources) is its own contract:
> [docs/domain/skillnode-emblem.md](../../docs/domain/skillnode-emblem.md).

How the concentric rings around a `SkillNode` are sized. One convention, one
formula, so radii stay legible "going forward" instead of each ring re-deriving
its own.

## SkillNode-visuals-v2 (milestone #16) — cut over; SkillNode composes it

`skill_node/visuals/` holds the component family (`SkillNodeVisual` /
`SkillNodeRingVisual` base classes in that same directory, plus `inner_disk`
(whose polygon carve is a height-field dent in its own shader — see below), `rim_ring`,
`core_halos`, `node_visuals_composite`, plus `rim_bonuses` / `rune_ring` —
shelved out of the composite, see below)
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
in `_enter_tree`. Its positive control (a component that *asked* for the clock
does get it) drives a standalone `rune_ring.tscn`, since #238 shelved the last
animating child out of the composite; keep a positive control of some kind, the
`assert_false` half alone can't tell "correctly gated" from "clock broken".

### CoreHalos GIMBAL (#138): a real quaternion-composed nested-ring gyroscope

The old `_draw_gimbal()` drew three co-planar `draw_arc` sweeps at increasing
radii with phase offsets — angular offset within one plane, never a tilt, so
it never read as a gyroscope. The issue owner rejected "faked tilted
ellipses" and asked for a real gyroscope: N rings where the outer ring spins
independently and each inner ring's orientation *depends on* the one outside
it, like an actual gimbal mount. This is the first use of `Quaternion`/3D
math anywhere in `skill_node/visuals/` — worth knowing before reaching for a
2D-only trick on the next "reads as 3D" component.

**The mechanism is quaternion chain composition, not per-ring phase math.**
Each ring's local spin axis (alternating `Vector3.RIGHT`/`Vector3.UP` — never
the ring's own normal/Z, which would just be an invisible in-plane spin) is
composed onto the *previous* ring's accumulated rotation:
`chain[i] = chain[i-1] * Quaternion(axis_i, base_tilt_i + spin_i)`. That's
the literal physical mechanism of a gimbal (child pivot mounted on the parent
ring), which is what makes "inner depends on outer" true by construction
rather than by a hand-tuned offset. The `base_tilt_i` constant matters on its
own: without it every ring starts coincident (all spins are 0 at
`anim_time == 0`) and can re-coincide whenever rates line up — the
persistent orthogonal "cage" read needs a standing per-ring offset, not just
differing speeds.

**Each ring is a HOOP (an uncapped cylinder slice) at its own staggered
radius, not a flat washer and not a 1D loop.** Two mistakes were tried and
corrected here, both worth knowing before touching this again:

- *Same radius for every ring* reads as one gyroscope cage where every ring
  is the same size, not "inner/mid/outer" — `_gimbal_runs()` staggers radius
  per ring (`ring_r = base_r * (1 + i * GIMBAL_RADIUS_STEP)`), same shape as
  RINGS' own radius step.
- *Radial band offset* (two concentric circles at `r ± half_w`, both in the
  ring's own Z=0 local plane) makes every ring a flat annulus — a disc with a
  hole, which foreshortens into a thin ellipse-shaped OUTLINE when tilted,
  never a band with real surface facing outward. The fix is an **axial**
  offset: the two rim loops are offset along the ring's OWN spin axis
  (`Vector3(cos t, sin t, 0) * r` shifted by `±half_w` in local Z, *before*
  rotation), so the band is a genuine tube wall. Face-on, the two rims nearly
  coincide (a tube seen end-on is just a ring); tilted, you see the actual
  wall width — the same way a real bracelet or a Halo ringworld segment
  reads. This is the literal "flat strip bent and connected end to end" /
  "uncapped cylinder slice" read that was asked for; a flat annulus is not
  the same shape as a hoop, even though both are legitimate (non-"faked")
  projections of *something* real in 3D — the point is which 3D shape.

Both rim loops are rotated by the same `chain[i]` and orthographically
projected (drop Z) — because they undergo the *identical* linear map, they
can't decouple into two disagreeing curves.

**Batch the whole layer into ONE `canvas_item_add_triangle_array`, with our
own indices (#239).** The band offset is axial rather than radial, so a
heavily tilted ring's projected band can fold over itself in 2D — Godot's
ear-clipping triangulator can throw "Invalid polygon data, triangulation
failed" on that silhouette (hit empirically once the hoop offset landed; the
earlier radial-offset annulus never had this problem, since a purely radial
offset can't fold). The original fix was a per-segment `draw_primitive` (an
explicit 4-point quad, no triangulation step). That worked but cost ~384
`draw_*` calls per gimbal plus two `draw_polyline_colors` per run — at 22
gimbals it dropped a high-end GPU to ~43fps (#239). `_gimbal_batch()` now
accumulates every run's fill quads **and** both glow strips into one flat
vertex/color/index buffer (each quad = two triangles we index ourselves, so
the triangulator still never runs — the fold stays moot), and `_draw_batch()`
submits it as a single `canvas_item_add_triangle_array`. Measured 8963→340
draw calls for 200 three-ring gimbals (~26×). Two things to keep:
- **Supply the indices; never fall back to `draw_polygon` over a run.** The
  whole point is that explicit indices sidestep triangulation — a `draw_polygon`
  would re-introduce the fold failure.
- **Fold the glow into the same buffer, not separate `draw_polyline_colors`.**
  Post-fill-collapse the polylines would dominate (≈12/gimbal × 200 = 2400
  calls); `_append_glow_strip` rebuilds them as thin miterless quads for zero
  extra draw calls.

**The ring must pass over AND under the SkillNode's own disk — this needs a
second CanvasItem, not draw order.** A point on the ring is in front of the
disk when its rotated Z is positive (the disk sits at the screen plane,
Z=0) and behind it when negative. One CanvasItem's `_draw()` can't interleave
with `InnerDisk`/`RimRing` at two different z-levels, so `core_halos.tscn`
carries a child, `GimbalBack` (`core_halos_back.gd`), with `z_index = -1`
left `z_as_relative = true` (the default) — that's a *relative* offset that
nudges it behind `InnerDisk`/`RimRing` (both default `z_index = 0`) within
this node's own stacking, without fighting the SkillNode root's own
absolute/graph-level `z_index` (`skill_node.gd` toggles that for
sensed-fog ordering — ride that chain, don't override it). `CoreHalos`
itself stays the front layer, unchanged in tree position, so RINGS/ORBIT/COG
keep drawing on top exactly as before.

Each ring's sampled points are split into contiguous runs by the sign of
rotated Z (`_split_ring_runs`) — generically one front run + one back run per
ring, since a planar ring crosses Z=0 at exactly two points per revolution.
`CoreHalos._gimbal_runs()` is **pure geometry, no `draw_*` calls** — both
layers call it and always agree, instead of one recomputing and the other
reading stale data. **Both layers must recompute every redraw, and both must
be told to redraw every tick**: Godot only accepts `draw_*` /
`canvas_item_add_*` calls for a CanvasItem while *that* item is the one
currently drawing, so the shared draw helper (`_draw_batch(target, batch)`,
fed by `_gimbal_batch(runs)`) takes the target CanvasItem explicitly rather
than assuming `self` — `target.get_canvas_item()` binds correctly to the
target's own canvas item, but only works if that item is presently inside its
own `_draw()`. `core_halos_back.gd` therefore calls `_halos._gimbal_runs()` +
`_halos._gimbal_batch()` (data) then draws the result itself in its own
`_draw()`, rather than asking `CoreHalos` to draw on its behalf.
And `CoreHalos._process()`/`_redraw_all()` explicitly call
`_back_layer.queue_redraw()` alongside `queue_redraw()` on itself — the base
class's shared clock (`SkillNodeVisual._process`) only redraws the node it's
declared on, so without this the back layer draws once and freezes mid-spin
while the front half keeps animating. A "does it crash" test won't catch
that; only watching it animate will (`test_core_halos_gimbal.gd` covers the
crash/split/pure-function-of-time properties it *can* assert; the visible
motion still needs an eyeball pass in the sandbox).

`CoreHalos` deliberately has no `class_name` (matching every other leaf
component in this family — only the base classes declare one), so
`core_halos_back.gd` accesses its parent via untyped `get_parent()` and duck
typing (`_halos.is_gimbal_active()`, `_halos._gimbal_runs(...)`) rather than
a static `CoreHalos` type reference.

**Inner-face glyphs live in the 3D substrate, not the 2D `_draw()` path.**
They were flagged as "way more than we can fake in 2D without building some
WILD machinery" (a 2D `_draw()` has no UVs; a per-instance glyph would force
baked per-instance textures). The real-3D gimbal (`skill_node/visuals/gimbal_3d/`,
see next section) gets them for free — each band is a real mesh with authored
UVs (u around the ring, v across the inner wall), so the `SOLID_GLYPH` style
scrolls an emissive rune strip down the inner face and it wraps the whole hoop.
Don't try to reintroduce this on the 2D path.

### 3D gimbal showcase (#239): the boss-tier looks, on a real SubViewport

`skill_node/visuals/gimbal_3d/` is a real-3D rebuild of the gimbal for boss
differentiation — the same quaternion chain (shared `AXES`/`RATE_BASE` + the
per-ring standing tilts) driving hand-built **annular-prism bands** (flat
rectangular-cross-section rings, not round `TorusMesh` donuts) whose `Basis` is
set per-frame, inside a `SubViewport` world with a glow `Environment`. The
over/under interleave is the depth buffer, not a hand-split front/back
CanvasItem, and the look is emissive shaders (the CPU stacked-stroke fake can't
reach neon/glass/glyph).

- **Chain index 0 is the OUTERMOST band (the parent).** The chain composes each
  inner ring's spin onto the accumulated outer rotation, so radius must *shrink*
  with chain depth — otherwise spinning the outer ring wouldn't carry the inner
  ones and the gimbal dependency reads backwards. Outer rings also spin slowest
  (rate grows with depth), so the inheritance is legible: inner rings whirl fast
  within the slowly-reorienting outer frame. (The 2D CoreHalos GIMBAL still maps
  radius the *other* way — smallest at the chain root — a latent inversion not
  yet backported; it's tiny/core-gated so nobody's called it.)
- **The band is built around the Y axis** (`_build_band_mesh`), so the same
  constant `MESH_CORR` (90° about X) rotates its axis into local Z (matching the
  2D hoop) before the chain `Basis` is applied: `basis = Basis(chain) * MESH_CORR`.
- **`facets` (segments) is the angular/PCB dial** — low is faceted, high is
  smooth. The de-donut win is the *flat* rectangular cross-section, independent
  of facet count.
- **`thickness` (#239) is a NUDGE of radial depth, tweakable independently of
  `band_width` (axial).** The band went from a zero-thickness cylinder slice to a
  hollow ring — `_build_band_mesh` emits an outer wall + inner wall + two rims.
  No stock primitive gives flat walls with radial thickness decoupled from axial
  width (a `TorusMesh` locks the two equal and is round), so it's a hand-built
  `ArrayMesh` (via `SurfaceTool`). `thickness == 0` degenerates to the single
  outer wall (the old thin slice). The band's outer radius rides in an
  `outer_radius` meta on the `MeshInstance3D` (a custom mesh has no
  `CylinderMesh.top_radius` to read) — see `test_chain_root_is_the_outermost_ring`.
- **The `SOLID_GLYPH` runes inscribe only the inner wall, and are rim-aware by
  UV.** `_build_band_mesh` hands the inner wall clean `v ∈ [0,1]` (the glyph
  band, so runes run centered down it) and parks the outer wall + both rims at
  `v = OUTER_V (2.0)`, where `gimbal_glyph.gdshader`'s band mask is 0 — so the
  rims stay bare metal. **Gotcha this fixed:** a stock `CylinderMesh` side wall
  maps `v` to `[0, 0.5]` (caps would take `[0.5, 1]`), which is why the glyphs
  drew off-center before the re-mesh — the shader assumed `v ∈ [0,1]`. Owning the
  mesh's UVs is what makes both "centered" and "rim-aware" true by construction.
- **Culling is per-style (#239).** `SOLID_GLYPH` and `UNIFORM_GLOW` are solid
  bodies → `cull_back` (on the glyph, the near inner wall is occluded by the near
  outer wall anyway, so you read the *far* inner face lit through the near gap).
  `HOLO_GLASS` stays `cull_disabled` — a transparent hoop wants both walls'
  fresnel visible through each other.
- **Gotcha that shipped with #239's initial landing: Godot's front face is
  clockwise as seen from the camera, not counter-clockwise.** `_quad()`'s
  corners were originally emitted in the order that reads CCW when you trace
  `a→b→c→d` looking at the intended outward normal — the OpenGL-textbook
  convention — but Godot culls that winding as a *back* face. Confirmed
  empirically: a minimal `SurfaceTool` quad facing the camera rendered
  invisible under `cull_back` with that ordering, and rendered lit as soon as
  two corners per triangle were swapped. Symptom was specific to `SOLID_GLYPH`
  (the only style whose shading isn't sign-invariant — `UNIFORM_GLOW`'s
  `abs(dot(NORMAL, VIEW))` rim term and `HOLO_GLASS`'s `cull_disabled` both
  mask a flipped winding): the hoop rendered as a flat, unlit black band with
  no metal sheen, and the ring read as a solid disc instead of an open hoop —
  because the *far* wall (whose outward normal now pointed away from both
  camera and light) was surviving the cull instead of the near one. Fixed by
  swapping the two non-shared vertices in each emitted triangle in `_quad()`;
  `a`/`b`/`c`/`d` and their per-corner normals/UVs are untouched, so no caller
  changed. **Don't re-derive winding by eyeballing "does this look CCW" —
  Godot's actual convention is CW-from-camera; verify empirically
  (`SurfaceTool` + `cull_back` + sample a pixel) before trusting the geometric
  intuition.**

- **Same contract by intent:** consumes `tint` (ownership, like CoreHalos'
  `entity_tint`) + `ring_count` + `spin_speed`; the three looks are one `Style`
  enum swap (UNIFORM_GLOW / HOLO_GLASS / SOLID_GLYPH), so a boss tier is an enum
  pick.
- **One shared `ShaderMaterial` per style, tint as an `instance uniform`** —
  same batching discipline as inner_disk/rim_ring. The `SOLID_GLYPH` glyph strip
  is a plain (non-instance) `uniform sampler2D` baked once into a `static var`
  (identical for every rig, like the diamond LUT), so it doesn't force the
  duplicate-material escape hatch.
- **The glow lives in the SubViewport's own `Environment`**, not a global
  `WorldEnvironment` — that isolated world is why these can bloom even though the
  main game has no project-wide glow, and it's the actual reason 3D beats the 2D
  stacked-stroke fake here.
- **Not yet wired into the live SkillNode pipeline** — it's a showcase
  (`gimbal_3d_showcase.tscn`, auto-discovered as the sandbox "Gimbal 3D" tab) for
  evaluating the look. The intended integration is **one small `SubViewport` per
  boss** (a `TextureRect`/`Sprite2D` composited at the node), NOT per node —
  bosses are rare, and the whole 3-gimbal showcase (9 bands + glow) measured
  **11 draw calls / ~cheap**, so a handful of tiny per-boss viewports is
  affordable. Lifting *every* node into 3D / MultiMesh scaling stays de-scoped
  while halos are core-gated (see #239).
- **Shaders are verified under `xvfb-run … --rendering-driver opengl3`**, never
  headless alone — GLSL doesn't compile under the dummy renderer (see
  `godot-workflow.md`). `test_gimbal_3d.gd` covers only what GDScript can assert
  (ring count, material/shader resolves, clock-driven re-orient); the look is a
  screenshot.

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
/ CorePresence) and shows [SensedOutline] — a **non-shader**
`SkillNodeVisual` that `_draw`s a faint archetype-tinted ring. Two properties are
load-bearing:

1. **Archetype-only is STRUCTURAL, not enforced by `visible=false`.** SensedOutline
   reads only `archetype_tint`, never `entity_tint` — so a sensed node *cannot*
   draw its owner by construction. That's the property the per-viewer info gate
   (next layer up, see `docs/domain/vision-system.md`) is meant to build on.
2. **Zero instance-uniform slots (#172), same gate as fog-hidden.** Hiding the
   `ShaderStack` — not each child — flips every shader child's
   `is_visible_in_tree()` false in one move, while CorePresence keeps its own
   default-hidden `visible` flag. `_apply_sensed()` resolves ShaderStack by
   **direct child path**, NOT a `%`-unique-name `@onready`, so the `sensed` setter
   works before the node enters the tree: `instantiate()` then `sensed = true`
   hides the stack *before* the shader children's `_ready` runs, so they never
   bind a material. A `%`-name returns null until in-tree, which would leave the
   stack visible through the children's `_ready` and claim a slot. `SkillNode`
   also hides `BaseCircle` when sensed (owner-coloured wash). Guarded by
   `test_node_visuals_contract.gd`'s `*_sensed_*` tests.

### SHELVED (#238): RimBonuses and RuneRing are out of the composite

Both were authored by the design labs as **alternate** looks, not simultaneous
layers, and they crowded each other out (#132: the rune ring "reads as
invisible, crowded out by rim_bonuses diamonds"). Verdict, 2026-07-31: **CUT
both, shelved not deleted.**

- `rim_bonuses.tscn` / `rune_ring.tscn` and their scripts stay in the repo, and
  stay instanced in the sandbox host's Node Visuals tab
  (`skill_node/visuals/panel/node_visuals_panel.tscn`). **That preview is the
  shelf** — there's no `shelved/` directory, and adding one would just churn
  paths.
- Their instances are gone from `node_visuals_composite.tscn`, and the wiring
  (`_rim_bonuses` / `_rune_ring`, `bonus_inward_growth`,
  `RIM_BONUS_DEFAULT_WIDTH`, the `_sync_stake` dial block) is gone from
  `node_visuals_composite.gd`.
- **Nothing was left hidden-but-instanced, deliberately.** A level carries
  ~500-2500 SkillNodes, so an unused child is tree nodes, `_ready` work and
  potentially an instance-uniform slot on every one of them — the same argument
  that retired the RimRing2-4 placeholders in #172. See
  `.claude/rules/skill-node-scale.md`.
- Re-adding the *scene* is instancing it back under `ShaderStack`. Deleting
  `rim_bonuses.tscn`/`rune_ring.tscn` permanently is equally live as an option —
  the decision was explicitly deferred, not made.

**#341 reclaimed the dial's FUNCTION, not the scene.** Stake/cap depth had no
*partial-fill* read from #238 until #341: `SkillNode.radius` growing with
`stake_level` (`stake_radius_delta`) covered "this node is staked" as physical
size, but "1/3 vs 3/3 allocated" was unvisualized. That gap is now closed as an
additive term folded straight into `rim_ring.gdshader` (`fill_current`/
`fill_max`, forwarded from `node_visuals_composite.gd`'s
`allocation_level`/`stake_level` in `_sync_stake()`) — RimRing draws the dial
itself; there is no separate CanvasItem for it. `rim_bonuses.tscn`/
`rune_ring.tscn` stay shelved-but-present for their OTHER encoders (rim gems,
rune band) that never got a reclaim.

**Two decisions worth pinning, since both get re-litigated as "why isn't this
animated / why does it start at the top" otherwise:**

- **No spin.** The shelved implementation spun the lit arcs continuously —
  purely to hide a parked asymmetric fixed-start-angle artifact, not because
  motion was ever the intended read. RimRing's dial is fully static: no `TIME`
  in the shader, no `_process` clock on RimRing (`test_node_visuals_contract.gd`
  asserts a static rim never ticks). The next decision is what actually fixes
  the artifact the spin used to paper over.
- **Anchored at 12 o'clock, grows outward symmetrically.** Lit slots are NOT
  filled contiguously from a fixed start angle (that was the artifact). Slot 0
  is centered at top; every state reads bilaterally symmetric about the
  vertical axis for every `M`, not just even `M` — realizing an odd `M`
  symmetrically needs a small preference order over which self-mirrored slot
  (top, and for even `N` also bottom) to use, since a single nested
  "add-the-next-symmetric-unit" growth path provably skips some `M` values (see
  `rim_ring.gdshader`'s `rim_fill_lit()` for the worked derivation). `y`-asymmetry
  (top and bottom differing) is accepted and fine; left/right must not.

The dial's semantics, as reclaimed: `fill_current`/`fill_max` synced from
`allocation_level`/`stake_level`. `0/*` draws nothing at all — not even an
unlit slot outline. `M/N` with `N > 1` divides the circle into `N`
**evenly-gapped** slots (gap width a global shared uniform, applied uniformly
whether a slot is lit or not, so a partial fill still reads as evenly spaced)
and lights `M` of them, centered up. `M == N == 1` is a special case — a
single full ring with zero gap, not a 1-slot dial (a 1-slot dial would just be
"almost a full circle minus one gap", which isn't the same read as "fully
lit"); only `1/1` is gapless. The lit term is additive across the WHOLE
`inner_r`..`outer_r` band, strongest at the crest, stacking on top of (not
replacing) the existing `tint_mix` archetype swing — see `rim_ring.gd` and
`node_visuals_composite.gd`'s `_sync_stake()`.

### The carve glyph is folded straight into InnerDisk's own shader — not a composite sibling, not even a sibling node

There is no `WeldSymbol` node anymore. The glyph is
`carve_kind`/`carve_sides`/`carve_squish`/`carve_radius`/`well_depth`
`instance uniform`s on `inner_disk.gdshader` itself, pushed in the same
`_sync_material()` pass as the dome's own tint/highlight uniforms. The
composite only ever talks to `%InnerDisk`; there's nothing else to keep in
sync. See "The polygon carve: a regular-polygon bowl dent in the dome's own
height field" below for the geometry.

**Authored vs. effective (#285).** The five knobs above are `@export`s ONLY as
standalone-preview defaults. `set_carve()` stores the resolved [CarveShape]
itself and writes NOTHING exported; `_sync_material()` pushes the getter-only
`effective_carve_*` / `effective_well_depth` derivations, which read off the
shape when one has resolved and off the authored exports otherwise. That split
is the `@tool`-script rule in `godot-workflow.md` ("never write a DERIVED value
back into an `@export`") — `inner_disk.tscn`'s stray `carve_kind = 1` is a
fossil of the version that did. The geometry itself lives on
`PolygonCarveShape` (`sides` / `squish_x` / `radius` / `well_depth`), not on
the `CarveShape` base: only the polygon path reads it, so a base-class field
would be one `GemCarveShape`/`TextureCarveShape` have to document as ignored.

**`PolygonCarveShape.well_depth` uses a NEGATIVE "inherit" sentinel**, resolved
on the CPU in `InnerDisk.effective_well_depth`. It must never reach
`set_instance_shader_parameter` — the uniform is `hint_range(0.0, 1.0)` and
would clamp a negative to `0.0`, i.e. "no dent", silently flattening every
shape that inherits. A deliberate `0.0` stays meaningful and distinct.

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
rim can't drift onto two different light models. The polygon carve's math
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

### The polygon carve: a regular-polygon bowl dent in the dome's own height field

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

**Regular polygons only, decomposed into `carve_sides` flat facets** — the
side count comes from the node's real archetype, via the `carve_shape` `.tres`
it references in `skill_node/visuals/emblem/shapes/`. Each
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
direction) — so `carve_kind == CarveKind.NONE` (or any pixel outside the
glyph) renders byte-identical to the plain dome; the shader only branches
into the new path when the sampled point is actually inside the bowl
(`bowl.x > 0.0`).

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

### The gem crown (loot relic, #168): a precomputed LUT, not per-pixel facet math — because every instance is IDENTICAL

`InnerDisk`'s `carve_kind == CarveKind.GEM` (the `SkillDustAddon` relic's
gem-cut glyph) is a second height-field glyph alongside the polygon carve, but
built differently on purpose. The polygon's shape varies per node (different
archetype → different `sides`/`radius`), so it has to stay an analytic
per-pixel formula (`sn_polygon_facet`/`sn_bowl_drop`). The gem crown is the
SAME shape on every relic — no per-instance parameter varies it — so
recomputing its `atan2`/`mod`/facet math per pixel, per instance, every
frame, buys nothing. Instead `InnerDisk._build_gem_lut()` (lazy
`static var _gem_lut`, same caching shape as `_shared_material`) bakes a
small texture (table flat-depth region + tapering shoulders down to the
girdle then a pavilion to the culet, computed with a GDScript twin of the
facet math — see below for why that's fine here) ONCE, and
`sn_gem_bump()` (`lighting.gdshaderinc`) just decodes it per pixel.

**Why the LUT doesn't break batching, when the rule elsewhere says samplers
force `resource_local_to_scene`:** that constraint is specifically about a
sampler that VARIES per instance (rim_ring's custom-curve escape hatch). This
LUT is identical for every `InnerDisk`, so it's bound as a plain
`uniform sampler2D gem_lut` (NOT `instance uniform`) on the one shared
`ShaderMaterial`, set once in `_ready()` — every instance samples the same
texture object, same as every instance already shares the one
`ShaderMaterial` itself. Only a per-instance-varying sampler would force the
duplicate-material path.

**Why the GDScript bake isn't the "CPU twin of the shading formula"
anti-pattern the polygon carve retired** (`weld_symbol.gd`'s old
`_disk_shade()`, warned about above): that anti-pattern was two independently
*maintained* implementations of the same formula drifting apart over time.
Here there is only ONE implementation — the GDScript bake — and the shader
never re-derives the geometry, only decodes the baked texel. There's nothing
for it to drift from.

Encoding: R = `drop / SN_GEM_DEPTH_SCALE` (0..1), GB =
`grad / SN_GEM_GRAD_SCALE` remapped -1..1 → 0..1, A = the silhouette's
**antialiased coverage** (1 well inside, ramping to 0 just outside over
`GEM_EDGE_AA_TEXELS`), which the shader uses as a blend weight, never as a
`> 0.5` cutoff — a hard 0/1 alpha here plus a hard branch in the shader was
precisely what stair-stepped the gem's outline; `test/unit/test_carve_shape.gd`
(`test_gem_edge_coverage_is_antialiased`) covers the fix. **Divergence to
mind:** `TextureCarveShape.bake_lut()` (#246, arbitrary-art carves,
`skill_node/visuals/emblem/texture_carve_shape.gd:76`) still writes a hard
`1.0`/`0.0` alpha for its mask — same R/GB encoding otherwise. #247's decode
is wired now (next section) and deliberately treats that alpha as a **blend
weight**, not a `> 0.5` gate, so softening the bake to the same coverage ramp
is a one-sided change needing no shader edit — but until it happens, the
arbitrary-art outline stair-steps exactly the way the gem's used to. The bake constants
in `inner_disk.gd` and the decode constants in `lighting.gdshaderinc`
(`SN_GEM_DEPTH_SCALE`/`SN_GEM_GRAD_SCALE`) must stay numerically in
lock-step — they're two halves of one encoding, not independently tunable.

**When to reach for this vs. the polygon's per-pixel formula:** if a future
glyph needs per-instance variation (different archetype, different sides,
different depth), it has to be the analytic per-pixel path like the polygon —
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
