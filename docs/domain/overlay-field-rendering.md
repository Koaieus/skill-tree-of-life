# Overlay field rendering (`FogOverlay`, `AuraOverlay`)

Both overlays draw **one screen-covering rect** whose fragment shader loops over
every circle in a uniform array. `FogOverlay` unions vision circles into a
darkness mask; `AuraOverlay` unions each entity's owned-node circles into a
territory wash, then takes a cross-entity `argmax` for the hard Voronoi cut
(#74).

This note records what was measured, and one attractive design that **does not
work**.

## CPU reference fold

Every element self-shades per fragment against the shared `vision_field` globals,
so the render path takes no CPU darkness sample. `VisionSourceIndex`
(`ui/fog_overlay/vision_source_index.gd`) owns the tile grid the GPU reads, and
retains `distances_near` as the **CPU reference the shader is pinned against**
(`test_vision_source_index.gd`): keep it in lockstep; it is not dead code. A
per-element CPU walk (a sample per SkillNode and Edge midpoint, each folding over
every source) was `O(elements x sources)` per frame; indexing it bought 14x and it
still cost 78 ms at 2000 nodes, which is why the pass was deleted rather than
indexed. **Measure the CPU first**: this subsystem's symptom was twice blamed on
the shader and was a CPU walk (see [graph.md](../../.claude/rules/graph.md)).

The cull is exact. `field_smin(a, b, k)` returns `b` *identically* when
`b <= a - k` (the blend factor clamps and the polynomial term vanishes). Call that
**erasure**: any source at `d >= 1 + k` is erased by a nearer one and contributes
nothing.

**The fold's order is pinned to the shader's.** `field_smin` is not associative,
so the result depends on visiting order. The fragment shader walks its tile's
circles in a fixed order (distance is per pixel; a GPU cannot sort), so the CPU
fold walks **the same order**, and `distances_near` never sorts by distance:
sorting drifts the darkness by up to 0.061 against a visible threshold of
`1/255 = 0.0039`. `test_indexed_fold_stays_in_lockstep_with_the_shader` pins this
against an independent transcription of the shader's fold.

## The GPU cost cannot be measured in CI — use the harness

`scenes/overlay_perf_harness.tscn`, run on **real hardware**:

```bash
godot --path . scenes/overlay_perf_harness.tscn
godot --path . scenes/overlay_perf_harness.tscn -- --counts=0,15,100,400 --frames=90
```

The dummy renderer (GUT, `--headless`) never runs a fragment shader at all.
`xvfb` + `opengl3` is **llvmpipe**, a software rasterizer: it cannot parallelize
the per-pixel loop the way a GPU does, so it overstates the loop's cost by an
unknown factor. A bad number there proves nothing, and a good one proves less.
The harness detects llvmpipe and prints a warning; heed it.

Read the **delta** (overlay-on minus overlay-off GPU ms) as circle count grows.
Linear growth ⇒ the loop is the ceiling. Flat ⇒ it never was, and the silent
256-circle cap (fixed in bd8b169) was the whole bug.

### Measured: the loop is linear, and the constant is small

AMD Radeon RX 7900 XTX (RADV NAVI31), Vulkan / Forward+, 1440×960, GPU ms/frame:

| circles | fog Δ | aura Δ | both |
|---|---|---|---|
| 0 | 0.018 | 0.018 | 0.039 |
| 15 | 0.060 | 0.072 | 0.132 |
| 100 | 0.290 | 0.259 | 0.371 |
| 250 | 0.406 | 0.497 | 0.878 |
| 512 | 0.799 | 0.971 | 1.724 |

**Linear, as predicted.** 250 → 512 circles is 2.05×; the fog delta goes
0.406 → 0.799 ms, i.e. 1.97×. The sublinearity below ~100 is fixed overhead plus
sparse circles not covering the screen, not a saving.

**But the constant is ~1.6 µs per circle per frame at 1440×960.** A realistic
late-game board — one viewer at ~100 owned nodes (fog) and four entities at ~100
each (aura, which packs *every* owner's nodes) — costs about **1 ms/frame on
this card**. Roughly 6% of a 60 Hz budget, for two overlays.

So #133's GPU half is **real but not urgent**. Note this is a top-end discrete
GPU; the cost is pure fill, so it scales roughly with fill rate. An integrated
GPU or a handheld is plausibly 8–15× slower, which turns 1 ms into most of a
frame. Re-run the harness before assuming.

**Trigger conditions for actually building the fix:** targeting integrated /
handheld hardware, or circle counts pushing past ~1000, or the overlays
acquiring a second full-screen pass. Until one of those lands, the 256-cap
(bd8b169) and the CPU quadratic were the bugs that mattered.

## Additive blending cannot compute a minimum. Don't bake the field.

Decision: the field is evaluated per fragment from the tiled circle data, never
baked into an offscreen texture by additive blending. Godot's canvas has no
`GL_MIN` blend mode, so the union of a bake would have to fall out of additive
blending, and **no additive blend computes a minimum**: for `N` identical inputs
additive accumulation yields `f(N * g(d))`, which equals `d` for every `N` only if
`g` is identically zero.

- **LogSumExp** (accumulate `exp(-k d)`, recover `-ln(sum) / k`) is biased by
  `ln(N) / k`, `N` being the circles at that pixel. Two coincident circles at
  `d = 1`, `k = 8` recover `0.913`; through the fog's `smoothstep(0.85, 1.0, .)`
  that is `0.38` vs `1.0`, against an 8-bit step of `0.0039`. The bias is
  density-dependent and fog radius is a stat, so a dense cluster would bulge past
  its own `vision_range`: a mechanical change, not a cosmetic one. A `1/255`
  budget needs `k > 15000`; fp16 (`use_hdr_2d`, the only float canvas target)
  flushes `exp(-k)` to zero around `k = 20`. Power-means carry the same bias.
- **Hard-min** via a 3D depth test or jump-flooding reintroduces the seam
  creases the smooth-min removed, and the blur added to re-smooth them has a width
  in world units that does not map onto `k`'s normalized-distance units.
  LSE-with-compensation needs a per-pixel estimate of `N`.

This is an architectural call that belongs in an ADR in `docs/adr/` (not yet
written).

### Two facts worth keeping from the exercise

`SubViewport.use_hdr_2d = true` ⇒ `Image.FORMAT_RGBAH` (RGBA16F), and values
accumulate **past 1.0**. With it `false` you get RGBA8 and the sum clamps at
exactly 1.0, silently.

Canvas `blend_add` is `dst += src * src.a`, **componentwise, including alpha**
(three stacked writes of `a = 1, 1, 0.5` leave `dst.a = 1 + 1 + 0.25 = 2.25`).
So with `COLOR.a = 1.0` the RGB channels add cleanly, but **alpha is not usable
as a data channel** — that's 3 payload channels per target, not 4.

## Shipped: world-space tiled binning (#177)

Circles are binned into a **world-space** uniform grid, and both fragment
shaders read only their own 3×3 tile neighbourhood instead of looping every
circle. Per-pixel cost is local circle *density*, independent of both total
circle count and zoom. `field_smin` itself is untouched — no new precision
surface, no bias, no blur — it's the same fold this file already documents;
only which circles get folded, and their traversal order, changed.

**Architecture: data textures, not a bigger uniform array.** `OverlayFieldTileIndex`
(`ui/overlay_field_tile_index.gd`) is the shared CPU-side grid builder, used by
both `FogOverlay` (wrapped by `VisionSourceIndex`, which keeps the CPU reference fold in
lockstep — see above) and `AuraOverlay` directly. It packs three `ImageTexture`s per build:

- `circles_tex` — one `vec4(x, y, radius, tag)` texel per circle (`tag` is
  `motion` for fog, `entity_index` for aura). Since #898 the aura's is two
  texels per rounded-cone primitive (see below); fog's is unchanged.
- `tile_index_tex` — one `vec2(offset, count)` texel per grid tile, into the
  flat index buffer below.
- `tile_indices_tex` — a flat `circle_count`-length buffer of circle indices,
  grouped by tile.

The fragment shader computes its own tile coordinate from `world_pos`,
`texelFetch`s the 3×3 neighbourhood's `(offset, count)` pairs, and walks a
genuinely **dynamic-count** inner loop (`for (int j = 0; j < count; j++)`) —
this is the standard tiled/clustered-shading pattern, not a `MAX_CIRCLES`-style
fixed cap with an early break. This is why circle count is no longer an array
bound: `_MAX_CIRCLES` on both overlay scripts is now a 20000-circle *sanity
ceiling* (loud-or-none per #133's acceptance bar), not a shader array size.
`AuraOverlay.MAX_ENTITIES` raised `8 → 32` (target scale is 20 entities); it's
still a real array bound (`entity_colors`, and the per-fragment `min_d[32]`
local array) because that data is genuinely small.

`entity_colors` is packed through `Emissive.tint_damped(entity.color,
Emissive.INERT)`, not the raw `Entity.color` (#899) — so a low-luminance hue
doesn't wash out against a high-luminance one at the same `intensity`; see
`docs/domain/hdr-color.md`.

Proven with a spike before building the rest: a minimal canvas_item shader
`texelFetch`ing a data texture, compiled and run under
`xvfb-run … --rendering-driver opengl3` (headless never compiles GLSL — see
`.claude/rules/godot-workflow.md`). Confirmed read-back matched to within one
8-bit framebuffer quantization step before committing to the architecture.

### Compiling clean is not rendering correctly — verify pixels

The xvfb compile checks and `test_indexed_fold_stays_in_lockstep_with_the_shader`
prove the shader compiles and that two CPU implementations agree; none runs the real
`fog.gdshader` / `aura.gdshader`. `scenes/overlay_shader_verify.tscn` renders the real
overlay scenes under opengl3 (its pixels are trustworthy, unlike llvmpipe's
timings), captures the viewport, and compares sampled pixels against the CPU
reference math. It covers single-circle and multi-tile-gather cases (three circles
in distinct grid cells, proving the 3x3 read finds the right circles and distant
tiles do not leak in).

```
xvfb-run -a godot --path . --rendering-driver opengl3 --quit-after 30 \
  res://scenes/overlay_shader_verify.tscn
```

The fragment shader samples `world_pos` at the pixel CENTER (screen pixel N is
world N+0.5); `Image.get_pixel(x, y)` reads the integer corner. A pixel-level
check must apply the +0.5 offset, or it disagrees by a few percent in a steep
gradient (the fog fade zone) while flat regions agree by coincidence.

### Tiling is not bit-identical to a global-array fold

`field_smin` is not associative. A shader that walked circles in global array order
and the tiled shader (tiles in `(dx, dy)` scan order, circles in build order within a
tile) are different traversals, so numerically different folds.

Measured in `test/unit/ui/test_tile_gather_fold_order_drift.gd`: **max drift
0.0026** across 3000 random probes (dense random fields, `union_smoothness =
0.12`), against the visible threshold of `1/255 = 0.0039` used everywhere else
on this page. Under threshold, but only by ~30% headroom — dense clusters with
larger `union_smoothness` could plausibly exceed it. This is a small, accepted
visual difference from a global-order fold, not a bug.

**CPU/GPU lockstep holds.** `VisionSourceIndex.distances_near` returns tile-gather
order, the same order the shader uses, so the CPU reference fold and the fragment
shader agree exactly (`test_indexed_fold_stays_in_lockstep_with_the_shader`,
tolerance `1e-5`).

### A floating-point trap in the grid origin — and why the margin is there

`OverlayFieldTileIndex.grid_origin` is derived from the circle set's own
bounding box (`min_pos - cell_size`). Without a safety margin, that puts the
bounding box's OWN extremal circle **exactly on a cell boundary**: its distance
from `grid_origin` is exactly one `cell_size`, so `floor(distance / cell_size)`
lands on precisely `1.0`. Floating-point rounding at that knife-edge is
order-of-operations-dependent — two algebraically identical but differently
coded computations of the same floor can round to *different* cells for that
one circle, silently moving it in or out of a query's 3×3 neighbourhood.

Caught empirically while writing `test_vision_source_index.gd`'s independent
shader transcription: it disagreed with the real index by `0.0022` on one probe
out of 1200, traced to exactly this. Fixed by nudging `grid_origin` an extra
`cell_size * 1e-4` further out, so every real circle's cell coordinate sits
strictly away from any boundary. Any future reimplementation of this grid math
(a shader-side rewrite, a different language) needs the same margin, or the
same class of 1-in-thousands mismatch reappears.

World-space bins beat a screen-space viewport cull (the "cheap interim step" in
#133): the cull does nothing when zoomed out to the whole graph, and needs a
refresh on every camera move.

## Shipped: the rounded-cone primitive (#897)

Territory is the *owned induced subgraph*, so the aura wants a band along each
owned edge, not just a disc per node. The primitive is a **rounded cone** — two
endpoints with radii, i.e. a trapezoid plus its two end circles, as one
closed-form distance. `ra == rb` degrades to a capsule, `a == b` to a disc.

**The distance is normalized, and that is the whole trick.** Define

```
d(p) = min over t in [0,1] of |p - lerp(a, b, t)| / lerp(ra, rb, t)
```

i.e. the factor the configuration must be scaled by for `p` to land on the hull
of the two discs. Level sets are scaled hulls, `d == 1` is the hull itself, and
`d` reduces *exactly* to `|p - a| / ra` at each end — so `field_smin`, the
`falloff` exponent and the `smoothstep` fade all apply to a cone with no change
whatsoever, and the band's width interpolates along the edge. A Euclidean
rounded-cone SDF would not have that property.

`ui/overlay_field_cone.gd` is the CPU reference; `field_cone_distance` /
`field_cone_project` in `ui/overlay_field.gdshaderinc` are the GLSL twins.
`test_overlay_field_cone.gd` pins the closed form against a brute-force sample
of the definition above, which is the only real check that the derivation — and
therefore the shader — is right.

### Two traps in the closed form

Minimizing the ratio gives a *linear* equation, so there is one stationary
point `t*`. Both traps are about not trusting it:

- **`t*` can sit past the pole.** `h(t)` has a pole at `t = -ra/(rb - ra)`, and
  in the nested case (one disc inside the other) the stationary point lands on
  the far branch. `a=(0,0) ra=10`, `b=(5,0) rb=1`, `p=(20,0)` yields `t* = 4`,
  which clamps to `1` and reports `15` where the true minimum is `h(0) = 2`.
  The fix is to take `min(h(0), h(1), h(clamp(t*)))` — correct always, and
  identical to `h(clamp(t*))` whenever that is meaningful.
- **A disc is `0/0`.** Every owned node ships as a degenerate cone regardless of
  degree (otherwise an isolated node vanishes), and there both numerator and
  denominator are zero. `clamp(NaN, 0, 1)` is *undefined* in GLSL, so the
  `l2 > 0 && |den| > 1e-8` guard is load-bearing, not tidiness.

The primitive is C1 across the cap→flank seam (pinned numerically): a crease
there is exactly the Mach band `field_smin` exists to avoid.

### The projection-dedupe invariant

A circle occupies one cell; a segment genuinely crosses many, so a cone is
bucketed into **every cell its AABB touches**. The alternative — inflating
`cell_size` to half the longest segment — makes every cell on the board hostage
to one long Delaunay bridge, so per-pixel cost would stop being local density.

Multi-cell bucketing means one gather's 3×3 can meet the same primitive
several times, and **`field_smin` is not idempotent**: `smin(d, d, k) == d - k/4`.
A double-fold would darken the field in a *grid-correlated* pattern — the
worst kind of artefact, because it looks like structure. So:

> A primitive contributes only from the tile whose cell contains `q`, the
> clamped orthogonal projection of the query point onto the segment.

`q` is the orthogonal projection, **not** the argmin `t*` of the distance —
they differ, and only the former is needed here.

This is exact, not merely duplicate-free. If the cone contributes at `p` at all
then `|p - c(t)| < (1 + k) * max_radius == cell_size` for some `t` on the
segment; `q` is the segment's closest point, so `|p - q| <= cell_size` and
`q`'s cell is inside `p`'s 3×3. Dropping the primitive when `q`'s cell falls
outside the 3×3 therefore drops nothing that could have contributed. `cell_size`
stays `(1 + k) * max_radius` — there is no pathological long-edge case to warn
about.

CPU and GPU can disagree about `q`'s cell on a knife-edge (the same
floating-point boundary the grid-origin margin below is about). That changes
which tile a primitive is folded *from*, hence fold order, never membership —
it is folded exactly once either way. No CPU consumer needs cone lockstep;
`VisionSourceIndex`, which does need lockstep, is on the circle path.

### Why the fog path did not move

`OverlayFieldTileIndex` runs **one** bucketing and **one** gather over cones,
with circles fed in as degenerate ones — no second implementation of the same
contract. The fog path is unchanged because of two properties, not by
inspection:

1. For a circle, `project` returns the stored centre with no arithmetic, so its
   cell *is* the cell it was bucketed into and the dedupe test always passes.
   The dedupe filters and never reorders, so the traversal order the shader and
   `VisionSourceIndex` share is untouched.
2. Only the *serialization* forks: `build()` still emits the 1-texel
   `circles_texture`, `build_cones()` emits `primitives_texture` — two RGBAF
   texels per primitive, `(ax, ay, ra, tag)` then `(bx, by, rb, unused)`.
   `fog.gdshader` and `vision_field.gdshaderinc` were not edited.

`test_tile_gather_fold_order_drift.gd` and `test_vision_source_index.gd` guard
this, unmodified. One note on sizing: the flat tile-index buffer is as long as
total bucket occupancy, no longer `circle_count`.

### The cone path's `tile_indices_tex` is 2D; fog's is still one row (#898)

Occupancy is what makes the 16384-texel `maxImageDimension2D` floor reachable
at ordinary scale: aura `cell_size ≈ (1 + k) · 48 ≈ 55 px`, a Delaunay edge
runs 150–300 px, so its AABB touches ~6–16 cells; ~800 owned nodes + ~1500
owned edges late game is on the order of 13–16k flat entries. Owner's call
(2026-09-16): wrap the buffer on the **cone build path only**, and file
DDA-tight bucketing (an occupancy *reduction*, not a limit removal) as a
separate `#140` child. So `build_cones()` lays the flat buffer out in rows of
`OverlayFieldTileIndex.TILE_INDICES_COLS` (4096) texels — entry `e` at
`(e % COLS, e / COLS)` — and `aura.gdshader` reads the row width back with
`textureSize(tile_indices_tex, 0).x`, so there is no uniform to desync. The
branch is keyed on the build path, not on "any segment present": a
degenerate-only cone set still ships wrapped because the aura shader always
fetches with the wrap formula. `build()` (fog) emits the same one-row image
it always has and `fog.gdshader`'s `ivec2(offset + j, 0)` fetch is untouched.
`test_overlay_field_tile_index_cones.gd` round-trips a >4096-entry build.

Still one row, and still bounded by that same limit: `primitives_texture` —
two texels per primitive, so it hits 16384 at 8192 primitives. That is well
above ordinary scale (~2300 late game) but below the 20000 sanity ceiling;
it was not part of the ruling and is left as is.

## Shipped: the aura draws the owned induced subgraph (#898)

`AuraOverlay` packs, per owning entity, one **degenerate cone per owned node**
(`A == B`, radius `node.radius × radius_multiplier` — regardless of degree, so
an isolated node still draws) and **one cone per edge whose two endpoints
share an owner** — the owned induced subgraph, in graph terms. A half-owned
edge draws nothing for the owner; an edge between two different owners draws
nothing for either (#140 decision 3, owner: *"nothing. option 1."*). Same-owner
means `owned_by` identity on both endpoints, never `ownership_bit` — this is
"same entity", not "mine". Self-loops are skipped: a second degenerate on the
same node would be a duplicate fold, and `field_smin` is not idempotent.

**Dumbbell knobs (decision 8).** An edge cone's end radii are the two aura
disc radii × `w`, `w = edge_width / (1 + L / edge_slack_length)`, evaluated
CPU-side per edge at pack time (`edge_width` default 0.6, `edge_slack_length`
default 300 px, `INF` disables the pinch — the quotient is simply 0). The
`smin` union with the full discs produces the neck; there is no second SDF.
`intensity`, `falloff`, `union_smoothness` apply to cones in the same
normalised-distance units as discs, so the three anti-Mach-band measures
(smin seams, smoothstep fade, dither) carry over untouched (decision 9).

**The shader's inner loop** fetches the two texels, runs the projection dedupe
(`field_cone_project` cell `!=` the tile being read → skip), then folds
`field_cone_distance` into the same per-entity `min_d` `smin` fold; the argmax
cut is unchanged. Expected, not a bug: a hub of owned degree *m* is covered by
its disc plus *m* cone ends, so the fold reaches a couple of px further there
(decision 7). `set_field(circles, colors)` survives as the disc-shaped door
(each circle expands to a degenerate cone) so the verify scene's disc case,
the caps test and any disc-only caller keep working; `set_cones` is the real
entry. The shader uniforms still say `circles_tex` / `circle_count` — pinned
by `test_overlay_uniform_caps.gd`; `circles_tex` now carries the 2-texel
primitives texture.

`scenes/overlay_shader_verify.gd` pixel-checks one cone with unequal radii
against `OverlayFieldCone.distance`; the mid-edge fade-zone sample is the one
that catches a broken dedupe (`smin(d, d, k) = d − k/4` moves alpha by ~0.05
in the fade band, above `_TOL`, while a flat-interior sample would pass).

### Why fog does not get cones (#140 decision 1)

`vision_range` base is 500 px (`entity/default_entity_board.tres`, PER only
scales it up) while procgen edges run ~150–300 px (`min_dist =
2·max_node_radius() + node_padding = 2·50 + 50 = 150` — the radius ramp's
asymptote plus the authored padding, `procgen/modules/first_level/topology.tres`, #783). Two 500 px discs 200 px apart differ from
their hull by `500 − √(500² − 100²) ≈ 10 px` at the waist, which
`union_smoothness` already fills — a vision cone is a visual no-op. It would
also have to teach `VisionCircles.has_point` (shared with `AiRecon`) and the
five consumers of `vision_field.gdshaderinc` the same primitive to stop the
fog lying about logical visibility. The aura is the real case: aura radius =
`node.radius × 1.5 = 48 px`, centres ≥150 px apart, so aura discs never touch
without an edge primitive. Re-open only if `vision_range` ever tunes below
~2× edge length.

## Known limit, deliberately

`AuraOverlay.MAX_ENTITIES = 32` is a *colour-array* bound, not a circle bound
(circles moved to data textures in #177 and have no such limit up to the
20000-circle sanity ceiling). The 33rd owning entity renders no aura. It warns
on overflow.

## Re-measured at #177's target scale: confirmed sublinear

`scenes/overlay_perf_harness.tscn`'s default sweep now includes 1000, 2000, and
4000 circles (previously topped out at 512). Re-run on real hardware (not
llvmpipe — see above) after #177 landed:

AMD Radeon RX 7900 XTX (RADV NAVI31), Vulkan / Forward+, 1440×960, GPU ms/frame
delta (overlay-on minus baseline):

| circles | fog Δ | aura Δ | both |
|---|---|---|---|
| 512 | 0.246 | 0.437 | — |
| 1000 | 0.369 | 0.535 | 0.618 |
| 2000 | 0.451 | 0.706 | 1.097 |
| 4000 | 0.807 | 1.393 | 2.123 |

**Sublinear, as the tiling design predicted.** 512 → 4000 circles is 7.8× the
count; the fog delta grows 3.28×, the aura delta 3.19×. (For reference, the
pre-#177 loop was measured *linear* on the same card — 250 → 512, a 2.05×
count increase, moved the fog delta 1.97×, i.e. proportional.) Growth here
isn't perfectly flat because the harness scatters circles at random over a
fixed viewport, so local per-tile density rises somewhat with total count too
— that's the expected shape for a density-bound cost, not a total-count-bound
one. Absolute cost at 4000 circles (both overlays combined, ~2.1 ms) is a
small fraction of a 16 ms/frame budget on this card, where the naive
extrapolation of the pre-#177 ~1.6 µs/circle/frame constant would have put a
single overlay at ~6.4 ms at that count. #177's acceptance criterion — overlay
cost decoupled from total circle count, local density only — holds.
