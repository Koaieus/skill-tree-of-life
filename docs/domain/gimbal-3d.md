# Gimbal 3D — the boss-tier core look

`skill_node/visuals/gimbal_3d/` is a real-3D gimbal: nested annular-prism bands
spun by a quaternion chain, drawn in a `SubViewport` world. The over/under
interleave is the depth buffer (no hand-split front/back CanvasItem) and the
look is emissive shaders. Every entity core wears it through `core_gimbal.tscn`
in the one `GimbalWorld` per viewport; the sandbox "Gimbal 3D" tab
(`addons/sandbox_host/tabs/17_gimbal_3d_tab.tscn`) and
`gimbal_3d_showcase.tscn` are the look bench. The slot it sits in is
[skillnode-visuals.md](skillnode-visuals.md) (Core presence).

Code: `gimbal_3d.gd` (`Gimbal3D`, the rig), `gimbal_chain.gdshaderinc` (the
spin), `gimbal_{uniform,glass,glyph}.gdshader` (the three styles),
`gimbal_world.gd` (the substrate), `gimbal_front_fog.gdshader`.

## Spin chain

- **Chain index 0 is the OUTERMOST band (the parent).** Each inner ring's spin
  composes onto the accumulated outer rotation, so radius shrinks with chain
  depth (`RADIUS_STEP`) and spinning an outer ring carries every ring inside it.
  The rate grows with depth (`GIMBAL_RATE_BASE * (1 + 0.55 i)`), so inner rings
  whirl fast inside the slowly reorienting outer frame. Axes alternate RIGHT/UP
  and each ring has a standing tilt of `PI * i / ring_count`.
- **The chain runs per vertex in the shader** (`gimbal_vertex()` off `TIME`);
  `Gimbal3D` never ticks. Each ring is a `MeshInstance3D` holding the shared UNIT
  band mesh, scaled by its `Basis`, with the per-ring instance uniform
  `chain = (index, ring_count, phase, spin_speed)`. The ring's `custom_aabb` is
  its rotation sphere, so culling stays exact while the shader moves it.
- The mesh bakes `MESH_CORR` (90 degrees about X) per vertex: the band is built
  around Y, and the correction swings its axis to local Z so it lies in the ring
  plane like the 2D hoop.
- `phase` offsets the spin clock so a board of rigs does not turn in lockstep;
  `CoreGimbal` derives it from `node_seed` (golden angle). It is pushed as an
  instance uniform, never a rebuild. `ring_count` comes from
  `Gimbal3D.rings_for_level` (two, plus one per ten levels, capped at 5).

## Band mesh

- Each band is a flat rectangular-cross-section ring (outer wall, inner wall, two
  rims), not a round `TorusMesh` tube. A hand-built `ArrayMesh` (`SurfaceTool`)
  is the only way to decouple radial `thickness` from axial `band_width`; both
  are fractions of the ring's own radius. `thickness == 0` degenerates to the
  single outer wall. `facets` is the angular dial: low is faceted, high is smooth.
- A ring's outer radius rides in an `outer_radius` meta on the `MeshInstance3D`
  (`test_chain_root_is_the_outermost_ring` reads it).
- **Rim-aware glyph UVs.** The inner wall carries `v` in `[0, 1]` (the glyph
  band, so runes run centered down it); the outer wall and both rims sit at
  `v = OUTER_V (2.0)`, where `gimbal_glyph.gdshader`'s band mask is 0, so only the
  inner face is inscribed and the rims stay bare metal. Owning the UVs makes
  "centered" and "rim-aware" true by construction.
- **Godot's front face is clockwise as seen from the camera.** `_quad()` emits
  triangles in that winding; a quad wound counter-clockwise (the OpenGL-textbook
  convention) is culled as a back face under `cull_back`. Only `SOLID_GLYPH`
  shows a flipped winding (its shading is not sign-invariant); verify winding
  empirically (`SurfaceTool` + `cull_back` + sample a pixel), not by eyeballing.

## Styles and materials

`Gimbal3D.Style` is one enum swap, so a boss tier is an enum pick: `UNIFORM_GLOW`
(evenly emissive), `HOLO_GLASS` (semitransparent, fresnel-lit edges),
`SOLID_GLYPH` (opaque metal hoop with glowing runes on the inner wall).

- Culling is per style. `SOLID_GLYPH` and `UNIFORM_GLOW` are solid bodies and
  `cull_back` (on the glyph, the near inner wall is occluded by the near outer
  wall, so the far inner face reads through the near gap). `HOLO_GLASS` is
  `cull_disabled`: a transparent hoop wants both walls' fresnel visible.
- One shared `ShaderMaterial` per style (cached in `static var _mats`), `tint` and
  `chain` as instance uniforms, so every ring batches. The glyph strip is a plain
  `uniform sampler2D` baked once into a `static var`, identical for every rig.
- `tint` is the identity colour lifted to the bloom tier
  (`Emissive.tint(tint, GLOW_STOPS)`); the shaders' EMISSION is shape only.

## Substrate

`GimbalWorld` is the single World3D per viewport, drawn by two SubViewports (back
half just under the node disks, front half at `ZLayers.GIMBAL`, fogged per pixel
off the shared vision field; it sits above FogOverlay so it fogs itself with
`gimbal_front_fog.gdshader`). The real 2D disk sits between the halves: hidden
exactly where a disk is, visible everywhere else, and opaque rings order
correctly because a clip plane does not care about draw order.

- **Coordinates:** 1 3D unit = 1 world px; 2D +y down = 3D -y; both ortho
  cameras look down -Z from `CAMERA_Z`, so a rig at 3D (x, -y, 0) sits on world
  px (x, y).
- **One World3D:** `WorldBack` owns it (rigs, light, environment exist once);
  `WorldFront` shares it. The cameras split the world at the ring plane by
  near/far (`clip_planes`).
- **Camera sync is one read, four consumers.** On `RenderingServer.frame_pre_draw`
  the root viewport's canvas transform x stretch transform (what is actually
  drawn, after Camera2D smoothing and limits) feeds both cameras and both
  composites via `map_view`. Zero frame lag by construction: `frame_pre_draw`
  fires after every `_process` and before the draw, and node transforms reach
  the RenderingServer synchronously.
- **Viewport size:** both SubViewports are the root viewport's pixel size (window
  px, not the stretch-logical size), so fill cost is real and texels are 1:1;
  both are 4x MSAA.
- **No glow inside.** `project.godot`'s `default_environment` (the game's bloom
  env) would otherwise apply to this world too, so the scene pins a plain
  no-glow Environment. HDR values ride the RGBA16F targets (`use_hdr_2d`) into
  the root viewport's single bloom pass (`hdr-color.md`, way 7).
- **Idle:** both render targets are disabled while no rig is on screen
  (`visible_rig_count`). Each holder carries a `VisibleOnScreenNotifier3D`, but
  a sleeping viewport culls nothing so its notifiers can never report
  "entered"; while asleep, `_sync_camera` wakes the world on a cheap
  sphere-vs-view test and the notifiers take over.
- **One world per viewport:** authored beside the Graph in `game_root.tscn` and
  found by group (`acquire`).
- **Editor:** `@tool` so an editor-hosted preview (the sandbox Node Visuals
  panel) spins real rigs; only an `acquire`-spawned world outside the edited
  scene runs (`is_live_for`). An authored one, or anything in the open `.tscn`,
  stays inert.

## Verification

Shaders are verified under `xvfb-run ... --rendering-driver opengl3`, never
headless alone: GLSL does not compile under the dummy renderer (see
`godot-workflow.md`). `test_gimbal_3d.gd` covers only what GDScript can assert
(ring count, material/shader resolves, clock-driven re-orient); the look is a
screenshot.
