# Rendering performance: draws, batches, and where the time actually goes

A cost model for 2D shader work in this project. The one-sentence version:
**at UI/sprite scale the fragment shader is free and the draw call is not**, so
optimize for *state uniformity* (fewer batch breaks) long before you optimize
shader math. Only fullscreen passes flip that ordering.

Companion to [overlay-field-rendering.md](overlay-field-rendering.md) (the
fullscreen case, where fragment cost *does* matter) and the "measure the CPU
first" section of [`.claude/rules/graph.md`](../../.claude/rules/graph.md).

## The hardware model, briefly

The GPU rasterizes geometry into **fragments** and shades them in lockstep
groups — a **warp** (NVIDIA, 32 lanes) or **wavefront** (AMD; 64 on GCN,
**wave32** for pixel shaders on RDNA2/3, which is what a 7900 XTX runs).

Two consequences worth internalizing:

- **Fragments come in 2×2 quads, never singly.** A wave32 is 8 quads. Fragments
  outside the triangle in a partially-covered quad still execute as *helper
  lanes* whose output is discarded — they exist so `dFdx`/`dFdy` (needed for
  mipmap LOD selection) have neighbours to difference against. So thin diagonals
  and tiny sprites cost far more than their pixel count suggests. A 1px line
  pays ~4× waste.
- **Cost scales with covered fragments, not with object count.** A 200×40 button
  is 8,000 fragments = 250 waves = sub-microsecond even for a heavy shader.
  A 1080p fullscreen pass is ~2M fragments = 65k waves, a ~250× jump. There is
  no middle ground in practice: things are either negligible or fullscreen.

## The multiplier this project actually runs at

Every cost model below is per-object. What makes them matter here is the count:

- **A level holds roughly 500–2500 `SkillNode`s**, and possibly more — the graph
  *is* the game, so map size grows with content rather than plateauing.
- **`Edge`s scale with them**, at a comparable order of magnitude (a connected
  graph of N nodes carries at least N−1 edges, and these graphs are not trees).
- **Up to a few hundred of each render on screen at once**, depending on zoom.

So the unit of judgement is never "does this cost much on one node" — it's that
number times several hundred, every frame. A component that draws 12 strokes is
a few thousand draw calls at screen scale; a per-node `ShaderMaterial` is a few
hundred unbatchable draws (see the per-instance-material trap below); an
`instance uniform` on a shared material is ~free *per draw* but still claims a
slot in a global buffer whose software-rasterizer cap is 4096 items (#172).

Two consequences that have already shaped the code:

- **An unused component in `node_visuals_composite.tscn` is not free**, even at
  `visible = false` — it costs tree nodes, `_ready` work, and potentially a
  uniform slot on every node in the level. That is why #238 shelved RuneRing and
  RimBonuses out of the composite rather than leaving them hidden, and why #172
  deleted the RimRing2-4 stake placeholders.
- **Per-node visual variation belongs in `instance uniform`s on one shared
  material**, never in a duplicated material. `InnerDisk` and `RimRing` both
  follow this; see [`.claude/rules/skill-node-visuals.md`](../../.claude/rules/skill-node-visuals.md)
  for the full contract, including the `is_visible_in_tree()` gate that keeps a
  fogged or sensed node at zero slots.

## The three input channels (and why the distinction is the whole point)

| Channel | Varies per | Cost |
|---|---|---|
| **Uniform** (`uniform vec4 tint`) | per *draw call* — constant across every fragment | free to read (lives in scalar registers), but **changing it splits the draw** |
| **Varying** (`UV`, `COLOR`, custom) | per fragment, hardware-interpolated | ~free |
| **Texture sample** | per fragment | latency/cache-bound; the real per-pixel expense |

A uniform is not "how a pixel gets its data" — it is *state bound before the
draw*. Therefore: **two things that need different uniform values cannot be the
same draw call.** Uniformity is the currency of batching.

(Shader **variants** are a fourth, unrelated thing: compile-time `#ifdef`
permutations producing separate compiled programs, selected per material at
load time, never per pixel.)

## What breaks a Godot 2D batch

Godot's canvas renderer walks items in draw order and merges consecutive ones
into a single draw call for as long as nothing in the bound state changes. The
batch breaks on:

- **a different texture** ← what a texture atlas fixes
- **a different material** — including the *same shader with different uniform
  values*, because a `duplicate()`d `ShaderMaterial` is a different material
- a different blend mode or `CanvasItemMaterial` flag
- a `Light2D` boundary, `clip_children`, or a `BackBufferCopy`

So: 200 sprites from 200 PNGs = 200 draws; the same 200 from one atlas can
collapse to 1. The fragment work is identical either way — the atlas buys you
**fewer texture binds**, i.e. fewer state changes, i.e. fewer draws.

### The trap: per-instance materials

Giving each `SkillNode` its own material so you can
`material.set_shader_parameter("aura_strength", x)` per node **guarantees one
draw call per node**, no matter how good the atlas is. Same shader, different
uniforms, unbatchable. This is the most common way a "cheap" per-node effect
becomes the frame's dominant cost.

The fix is to move per-instance data out of uniforms and into a channel that
interpolates for free without touching bound state:

- `modulate` / vertex `COLOR` — 4 floats, already wired
- UV offset (atlas region selection *is* this trick)
- `MultiMesh` `INSTANCE_CUSTOM` — 4 more floats per instance

**MultiMesh is not a magic fast path.** It's one mesh + one material + N
instances whose per-instance data lives in a *buffer indexed by `INSTANCE_ID`*
rather than in re-bound uniform state. State never changes, so it's one draw.
Anything expressible in ~8 floats of per-instance variation fits; anything
needing a genuinely different shader does not.

## Triage order

1. **CPU logic.** Measure it first. This project has been bitten three times —
   `Graph.get_neighbours()` (c5f3e42) and FogOverlay's per-element dimming pass
   (#133, then again as #414) — all read as "the shader is slow" and all were
   CPU walks. The fog one came back after being *optimised*; it stayed fixed
   once it was deleted.
2. **Draw call count.** Batch breaks, per-instance materials.
3. **Overdraw.** Stacked transparent fullscreen quads multiply fragment cost
   linearly: 5 alpha layers over 1080p = 10M fragments. Blended geometry can't
   be depth-rejected, so *every* layer shades in full — and in 2D everything is
   blended, so overdraw is always paid in full.
4. **Fragment ALU / texture cost.** Only reachable at fullscreen or heavy
   overdraw.

## Aside: can a uniform change mid-draw?

No — that constancy is what lets the value live in scalar registers. But four
things get you variation inside a single draw, and they're worth knowing so you
recognize them:

1. **Per-instance data** (`INSTANCE_ID` → buffer). The sanctioned route; what
   MultiMesh uses.
2. **Dynamically indexing a uniform array** with a per-fragment index. The array
   is bound state; *which element* is per-pixel. Costs the scalar-load
   optimization; Vulkan needs `nonuniformEXT` for descriptor indexing.
3. **Subgroup ops** (`subgroupBroadcastFirst`) — a value uniform *per wave*,
   differing between waves in one draw. Also how you get 32-pixel blocky
   quantization artifacts.
4. **Unsynchronized reads of concurrently-written memory** — SSBOs without
   barriers, or sampling the render target you're writing. Fragment ordering
   across a draw is *unspecified*, so output is non-deterministic frame to frame
   and vendor to vendor. A real glitch-art technique; never usable for anything
   that must look the same twice.

## Self-shading beats z-order occlusion for fog-of-war-style visibility (#413)

`FogOverlay` used to be the only thing that knew how dark a point in the
world is: it painted an opaque-alpha quad over the whole graph, and anything
that needed a DIFFERENT treatment (a visible node dimmed by distance instead
of fully blacked out, a sensed node/edge at a fixed low alpha regardless of
distance) had to *escape* that quad via z-index promotion, then have its own
darkness re-computed on the CPU to match what the quad would have painted —
`FogOverlay._apply_per_element_dimming`, an O(elements) walk (deleted by #414,
see below) that also forced
a per-instance `z_index`/`modulate.a` write, which is exactly what blocks
batching something into a single `MultiMeshInstance2D` (one CanvasItem, one
`z_index`, no per-instance property writes at all).

The fix for `Edge` (nodes are an explicitly out-of-scope follow-up — see the
issue): make the circle-union darkness field itself a **shared, global**
GPU resource instead of one material's private uniforms, so any shader can
sample it and compute its own alpha per-fragment, with no CPU-side z dance
and no per-element CPU darkness sampling at all:

- `ui/vision_field.gdshaderinc` declares the field data (`vision_circles_tex`,
  `vision_tile_index_tex`, `vision_grid_origin`, `vision_falloff`, …) as
  **`global uniform`**, registered in `project.godot`'s `[shader_globals]`
  section. `FogOverlay` is the sole writer
  (`RenderingServer.global_shader_parameter_set`); any other shader that
  includes the file is a reader. `vision_field_enabled` (also global) carries
  the one bit a raw darkness value can't: "zero circles because nobody has
  vision right now" (should read fully dark) vs. "zero circles because no fog
  system exists in this scene at all" (should read fully lit) — the two are
  indistinguishable from `circle_count` alone.
- `graph/edge_mesh.gdshader` includes that file and computes its own alpha
  per-fragment: hidden → 0, visible → the shared darkness ramp, sensed →
  ignore the ramp entirely (a fixed alpha baked in CPU-side already).
- The three-way hidden/visible/sensed classification itself still comes from
  the CPU (`VisionSystem`'s hop/reachability logic isn't the same computation
  as the raw circle field, and can't be — see `Edge.vision_visible`) but it's
  now a single bit written once per vision tick, packed into the otherwise-
  redundant alpha of the MultiMesh's spare colour channel, not a per-element
  darkness *computation*.

**The SkillNode follow-up landed (#414), and it is the same three lines.**
`inner_disk.gdshader` and `rim_ring.gdshader` each `#include
"res://ui/vision_field.gdshaderinc"`, carry a `varying vec2 world_pos` set in
`vertex()` as `(MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` (`MODEL_MATRIX` is
vertex-stage-only in canvas_item shaders, so it has to ride a varying), and
multiply their final **alpha** by `vision_field_dim(world_pos)`. That helper is
the whole contract: it folds in both the `VISION_VISIBLE_DIM_FLOOR` clamp and
the `vision_field_enabled` gate, so a consumer needs to know nothing else about
the fog. Alpha rather than RGB, deliberately — it matches what `modulate.a` was
reaching for, and scaling RGB would push HDR emissive tiers (RimRing's fill
glow, #389) below the 1.0 bloom threshold.

**What that bought, and the shape of it.** The per-frame fog tick went from
78.7 ms to 0.2 ms at 200 owned nodes on a 2000-node map — the sustained
framerate collapse reported from playtesting. Most of the win is not the
per-fragment sampling itself but what it *unblocked*: with nothing needing a
CPU darkness value, the surviving O(elements) pass has only a z band and a
boolean to write, and could move off `vision_render_tick` (every frame while a
circle animates) onto `visibility_changed` (once per allocation). **Deleting a
per-frame pass beats optimising it** — #133 optimised this same walk and it came
back one layer up. `test/perf/bench_fog_refresh_cost.gd` guards the number;
`test/unit/ui/test_fog_overlay_classification.gd` guards which signal owns the
walk, because the bench alone can't tell "deleted" from "moved somewhere
untimed."

## Godot's headless dummy renderer does not implement `MultiMesh` instance-data readback

`RenderingServer.multimesh_instance_set_color(rid, 0, c)` followed by
`multimesh_instance_get_color(rid, 0)` returns the *unset default*, not `c`,
under `--headless` — confirmed at the `RenderingServer` level, not just
through the `MultiMesh` resource wrapper. `instance_count` and
`get_instance_transform_2d`/`get_instance_color`/`get_instance_custom_data`
all silently no-op the same way; only plain scalar properties like
`instance_count` itself round-trip.

**How to apply:** a GUT test can never assert against a MultiMesh's actual
per-instance buffer. If a system pushes data into one, mirror the
CPU-computed values in a plain script property too (see `Edge.render_transform`
/ `render_color_a` / `render_color_b` / `render_vis_state`) purely so tests
have something real to read — the mirror isn't redundant, it's the only
thing `mise run test` can ever see.

## Related

- [overlay-field-rendering.md](overlay-field-rendering.md) — the fullscreen
  overlays, where fragment cost is real and the CPU fold is the bottleneck
- [`.claude/rules/godot-workflow.md`](../../.claude/rules/godot-workflow.md) —
  `PlaceholderTexture2D` collapses UVs; headless import does not compile GLSL
