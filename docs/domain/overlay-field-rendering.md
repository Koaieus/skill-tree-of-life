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

## If the harness says the loop is real: tile the circles, don't bake them

Bin circles into a **world-space** uniform grid (the same grid `VisionSourceIndex`
already builds on the CPU) and have the shader read only its own 3×3
neighbourhood. Per-pixel cost becomes local circle *density*, independent of both
total circle count and zoom.

This keeps `field_smin` exactly as-is, so the look is bit-identical — no new
precision surface, no bias, no blur. It's also what real engines do for many
overlapping lights, for the same reason: when the blender can't express your
union operator, make the loop short instead of eliminating it.

World-space bins beat a screen-space viewport cull (the "cheap interim step" in
#133): the cull does nothing when zoomed out to the whole graph, and needs a
refresh on every camera move.

Give the shader an offset+count into a flat, tile-sorted index buffer so there is
no per-tile cap. If you do cap per tile, #133's acceptance criterion binds:
**loud, or none.**

## Known limit, deliberately

`AuraOverlay.MAX_ENTITIES = 8` is a *colour-array* bound, not a circle bound.
The 9th owning entity renders no aura. Neither the tiling above nor the depth
-test sketch in #133 lifts it. It warns on overflow.
