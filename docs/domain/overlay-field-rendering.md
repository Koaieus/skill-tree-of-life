# Overlay field rendering (`FogOverlay`, `AuraOverlay`)

Both overlays draw **one screen-covering rect** whose fragment shader loops over
every circle in a uniform array. `FogOverlay` unions vision circles into a
darkness mask; `AuraOverlay` unions each entity's owned-node circles into a
territory wash, then takes a cross-entity `argmax` for the hard Voronoi cut
(#74).

This note records what was measured, and one attractive design that **does not
work** — so nobody spends another afternoon rediscovering it. See #133.

## The CPU cost was the measurable one, and it was quadratic

`FogOverlay._apply_per_element_dimming` samples fog darkness once per SkillNode
and once per Edge midpoint, and each sample folded over **every** vision source.
`O(elements × sources)` — and it runs **per frame**, not per turn, because
`VisionSystem` emits `vision_render_tick` from `_process` while any circle's
radius is animating.

| sources / elements | before | after |
|---|---|---|
| 150 / 300 | 17.8 ms | 1.21 ms |
| 512 / 800 | 150.9 ms | 4.59 ms |
| 2000 / 1500 | 1087.7 ms | 21.9 ms |

Fixed by `VisionSourceIndex` (`ui/fog_overlay/vision_source_index.gd`), a
uniform grid over the sources. This is the **second** time this subsystem's
symptom was blamed on the shader and turned out to be a CPU walk — see
[graph.md](../../.claude/rules/graph.md), c5f3e42. **Measure the CPU first.**

The cull is exact, not a heuristic. `field_smin(a, b, k)` returns `b`
*identically* when `b <= a - k` — the blend factor clamps and the polynomial
term vanishes. Call that **erasure**. The dimming pass only samples elements it
already knows are *visible*, so some source sits at `d <= 1`; any source at
`d >= 1 + k` is erased by that nearest one and contributes nothing at all.

## Don't "improve" the CPU fold's order. It is pinned to the shader's.

`field_smin` is **not associative**, so the fold's result depends on the order it
visits distances. The fragment shader has no choice: it walks its `circles`
uniform array front to back, because distance is per-pixel and a GPU cannot
sort. So the CPU fold must walk **the same array in the same order** — that's
why `VisionSourceIndex.distances_near` sorts candidate *indices* and never
candidate *distances*.

Sorting by distance is tempting (it enables an early `break`, and it makes the
result independent of `VisionSystem._circles`'s Dictionary iteration order). It
was measured: it drifts the darkness by up to **0.061**, against a visible
threshold of `1/255 = 0.0039`. A node in the fade zone would dim by a different
amount than the fog painted behind it — the exact mismatch the `_sample_dark`
docstring has always warned about. Order-independence is a *non-*requirement:
reordering the Dictionary changes CPU and GPU identically.

The `break` was redundant anyway. The grid already culls exactly, so the
candidate set is small and every omitted source is a provable no-op.
`test_indexed_fold_stays_in_lockstep_with_the_shader` pins this against an
independent transcription of the shader's fold.

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
(bd8b169) and the CPU quadratic (below) were the bugs that mattered.

## ⚠ Additive blending cannot compute a minimum. Don't bake the field.

The tempting design: give each circle **one quad** instead of making every pixel
loop over every circle, bake the union into an offscreen texture on change, and
reduce the per-frame cost to one texture sample.

Godot's canvas exposes no `GL_MIN` blend mode, so the union has to fall out of
additive blending. The classic trick is **LogSumExp**: accumulate
`exp(-k·d)` additively, recover `d = -ln(Σ exp(-k·dᵢ)) / k`. It looks perfect —
a genuine smooth minimum, computed by the blender, no loop.

**It is unusable here, and the reason is structural.**

LogSumExp is biased by `ln(N)/k`, where `N` is the number of circles
contributing at that pixel. Two coincident circles at `d = 1`, with `k = 8`,
recover `1 - ln2/8 = 0.913` instead of `1.0`. Push both through the fog's
`smoothstep(0.85, 1.0, ·)` and you get `0.38` vs `1.0` — a **0.62 error**, on a
scale where one 8-bit alpha step is `0.0039`.

The bias is **density-dependent**, and fog radius is a *stat*. A player owning a
dense cluster of nodes would watch their vision circle bulge outward past their
own `vision_range`. That is a mechanical change, not a cosmetic one.

You cannot tune out of it:

- Meeting a 1/255 error budget needs `k > 15000`.
- fp16 (`SubViewport.use_hdr_2d`, the only float canvas target) dies around
  `k = 20`: `exp(-20)` flushes to zero, the field reads empty, and the screen
  goes uniformly clear.

And it generalizes to *every* additive scheme, including power-means
(`(Σ dᵢ⁻ⁿ)^(-1/n)`), which carry the same `ln(N)/n` relative bias:

> For `N` identical inputs, additive accumulation yields `f(N · g(d))`. For that
> to equal `d` for **every** `N`, `g` must be identically zero. **No additive
> blend computes a minimum.**

Escape hatches all cost the thing you were protecting. Hard-min via a 3D depth
test or jump-flooding reintroduces the seam creases d267c89 removed, and the
blur you'd add to re-smooth them has a width in *world* units that doesn't map
onto `k`'s *normalized-distance* units. LSE-with-compensation needs a per-pixel
estimate of `N`.

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
both `FogOverlay` (wrapped by `VisionSourceIndex`, which also needs the CPU-side
per-element dimming pass to stay in lockstep — see below) and `AuraOverlay`
directly. It packs three `ImageTexture`s per build:

- `circles_tex` — one `vec4(x, y, radius, tag)` texel per circle (`tag` is
  `motion` for fog, `entity_index` for aura).
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

Proven with a spike before building the rest: a minimal canvas_item shader
`texelFetch`ing a data texture, compiled and run under
`xvfb-run … --rendering-driver opengl3` (headless never compiles GLSL — see
`.claude/rules/godot-workflow.md`). Confirmed read-back matched to within one
8-bit framebuffer quantization step before committing to the architecture.

### Compiling clean is not rendering correctly — verify pixels, not just GLSL

Everything above (spike, xvfb compile checks, `test_indexed_fold_stays_in_lockstep_with_the_shader`)
proves the shader *compiles* and that two *CPU* implementations agree with
each other — none of it ever runs the real `fog.gdshader`/`aura.gdshader` and
checks the pixels it paints. `scenes/overlay_shader_verify.tscn` closes that
gap: it renders the real `FogOverlay`/`AuraOverlay` scenes under opengl3 (a
correct, if slow, rasterizer for pixel output — unlike llvmpipe's *timings*,
its *pixels* are trustworthy), captures the viewport, and compares sampled
pixels against the same CPU reference math the overlays trust internally.
Covers both single-circle and multi-tile-gather cases (three circles scattered
across distinct grid cells, proving the 3×3 neighbourhood read finds the right
circles from the right tiles and that distant tiles don't leak in).

```
xvfb-run -a godot --path . --rendering-driver opengl3 --quit-after 30 \
  res://scenes/overlay_shader_verify.tscn
```

Building it caught one real bug in the shipped code and one in the test
harness itself — worth separating, because only one says anything about
`OverlayFieldTileIndex`:

- **Pixel-center vs. pixel-corner sampling (test-harness bug, not a shader
  bug).** The fragment shader samples `world_pos` at the pixel CENTER (screen
  pixel N is world N+0.5, standard rasterizer convention); `Image.get_pixel(x,
  y)` reads the integer corner. Comparing the two without a +0.5 offset
  drifted a few percent in a steep gradient (fog's default falloff=0.25 fade
  zone) even though flatter regions happened to agree closely by coincidence.
  Worth remembering if a future pixel-level check "mysteriously" disagrees by
  a small amount in the fade zone specifically.
- **Missing `await` on a coroutine call, not a rendering bug at all.** The
  verify script's first draft called `_verify_fog()` (which itself `await`s
  mid-body) without `await`ing it — `_ready()` moved on immediately, freed the
  `FogOverlay` node while `_verify_fog`'s suspended coroutine still held a
  reference to it, and resumed into a use-after-free segfault. This produced a
  crash that, while debugging it, looked suspiciously like it could be a real
  renderer limitation (a null `sampler2D` uniform, or single/dual-channel
  float `Image` formats). **Both of those hypotheses were tested in isolation
  after fixing the `await` bug and neither reproduced the crash** — the
  RF/RGF `Image` formats work fine, and a `null` texture on an empty circle
  set does NOT crash the compatibility renderer. Don't trust a crash's
  proximate symptom over an isolated repro; a coroutine call missing `await`
  is a mundane, easy-to-miss bug that can masquerade as something far more
  exotic.

### "Bit-identical to today" does NOT hold — measured, and it's small

This was this issue's own optimistic framing, and it's wrong for a documented
reason: `field_smin` is **not associative** (see the fade-zone drift already
on this page). The old shader walked circles in **global array order**; the
tiled shader walks tiles in `(dx, dy)` scan order and, within a tile, circles
in build order — a different traversal, so a numerically different fold.

Measured in `test/unit/ui/test_tile_gather_fold_order_drift.gd`: **max drift
0.0026** across 3000 random probes (dense random fields, `union_smoothness =
0.12`), against the visible threshold of `1/255 = 0.0039` used everywhere else
on this page. Under threshold, but only by ~30% headroom — dense clusters with
larger `union_smoothness` could plausibly exceed it. This is a real, if minor,
visual behavior change, not a bug; it was surfaced to the user rather than
silently shipped as "no visible change."

**CPU/GPU lockstep is unaffected.** `VisionSourceIndex.distances_near` used to
sort candidates back into global array order specifically to match the old
shader; it now returns tile-gather order instead — the same reorder the shader
itself uses — so `FogOverlay._apply_per_element_dimming` and the fragment
shader still agree with each other exactly
(`test_indexed_fold_stays_in_lockstep_with_the_shader`, tolerance `1e-5`). What
changed is only the *old-vs-new absolute value*, not CPU/GPU agreement.

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

## Known limit, deliberately

`AuraOverlay.MAX_ENTITIES = 32` is a *colour-array* bound, not a circle bound
(circles moved to data textures in #177 and have no such limit up to the
20000-circle sanity ceiling). The 33rd owning entity renders no aura. It warns
on overflow.

## Re-measuring GPU cost at #177's target scale

`scenes/overlay_perf_harness.tscn`'s default sweep now includes 1000, 2000, and
4000 circles (previously topped out at 512). Re-run it **on real hardware**
(not llvmpipe — see above) to confirm the delta stays sublinear in total circle
count at these scales; this repo's agents cannot do this themselves and it is
the actual acceptance criterion for #177, not just "it compiles and the tests
pass."
