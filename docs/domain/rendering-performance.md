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

1. **CPU logic.** Measure it first. This project has been bitten twice —
   `Graph.get_neighbours()` (c5f3e42) and `FogOverlay._apply_per_element_dimming`
   (#133) — both read as "the shader is slow" and both were quadratic CPU walks.
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

## Related

- [overlay-field-rendering.md](overlay-field-rendering.md) — the fullscreen
  overlays, where fragment cost is real and the CPU fold is the bottleneck
- [`.claude/rules/godot-workflow.md`](../../.claude/rules/godot-workflow.md) —
  `PlaceholderTexture2D` collapses UVs; headless import does not compile GLSL
