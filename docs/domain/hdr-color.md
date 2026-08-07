# HDR colour authoring: the `I` slider, the `Color` class, and bloom

How >1.0 colours get authored, stored, and read by the bloom pass. Settled by
probing in Godot 4.7 against #371; the `I`/stop datapoints below are empirical,
not reasoned.

## `Color` has no intensity field

The `Color` class is four unbounded floats — `r, g, b, a`. There is no `I` /
intensity member, no metadata, no flag bit. A `Color(1.353, 1.353, 1.353)` is
*just* three channels at 1.353; nothing remembers that it came from a picker at
I=+1. This is why the `Color` doc page says nothing about intensity — `I` lives
on `ColorPicker.edit_intensity`, not on `Color`.

**Why it matters:** programmatic glow needs no engine API and no recovery of a
"hidden state." Write the value you want directly:

```gdscript
const GLOW_VALUE := Color(1.353256, 1.353256, 1.353256)  # white +1 stop
```

## What the `I` slider does

`ColorPicker` doc on `edit_intensity`:

> The intensity is applied as follows: convert the color to linear encoding,
> multiply it by `2 ** intensity`, and then convert it back to nonlinear sRGB
> encoding.

So `stored = sRGB_encode( sRGB_decode(base) × 2^I )`. `I` is in **EV stops**
(+1 = ×2 linear), not a multiplier on the stored value. The stored `Color`'s
rgb is the *sRGB-encoded* form; the *linear* value the bloom pass thresholds is
`2^I` for white.

## Verified: exact piecewise sRGB above 1.0

Godot uses the piecewise sRGB function extended above 1.0, not a `^2.2`
approximation. Confirmed by setting white at I=+1..+4 in the picker and reading
the stored `Color` back:

| I (stops) | linear (2^I) | encoded (observed) | `1.055×L^(1/2.4) − 0.055` |
|---|---|---|---|
| +1 | 2.0  | 1.353256 | 1.3531 ✓ |
| +2 | 4.0  | 1.825    | 1.8248 ✓ |
| +3 | 8.0  | 2.454    | 2.4544 ✓ |
| +4 | 16.0 | 3.294    | 3.2944 ✓ |

Closes the open caveat in #371's verdict: the >1.0 path is exact piecewise all
the way up. Encoded growth is ~×1.35/stop asymptotically; linear doubles per
stop.

## Bloom threshold is in linear space

`Environment.glow_hdr_threshold` is a *linear* luminance value. The renderer
linearizes the authored (encoded) `Color` back via the same inverse piecewise
before the glow pass — so a tier authored at `+1` stop really is linear 2.0 at
threshold time. `glow_hdr_threshold = 1.0` therefore means *"any I > 0 stops
blooms"* for white; for non-white bases hinge it on `sRGB_decode(channel) × 2^I`.

This is the clean mental model #371's `inert / label / value / alert` tiers
map onto: tiers are named by **stops**, not hand-picked floats.

| tier     | I      | linear (white) | encoded       |
|----------|--------|----------------|---------------|
| inert    | 0      | 1.0            | `1.0`         |
| label    | ~+0.5  | ~1.4           | ~`1.15`        |
| value    | +1     | 2.0            | `1.353256`    |
| alert    | +2     | 4.0            | `1.825`       |

## Round-trips unclamped through `.tscn`

The property, the scene format, and the picker all carry >1.0 without clamp
(#371 W1). `theme_override_colors/font_color = Color(1.353256, …, 1)` saves,
reloads, and reads back identical. Also verified for `modulate` above 1.0.

The *ergonomic* way to author in-scene is the `I` slider; the *typed* way is
the `Color` constructor. They produce the same bytes.

## Generating tiers from a base + stops

When you'd rather name a tier by stops than commit the encoded float, use the
engine's own `Color.srgb_to_linear()` / `linear_to_srgb()` — same code path the
picker uses, so the output matches what would be hand-authored for the same
base + I:

```gdscript
func emissive(base: Color, stops: float) -> Color:
    var lin := base.srgb_to_linear() * pow(2.0, stops)
    return lin.linear_to_srgb()
```

Note these methods leave `a` untouched (alpha is always stored linear, never
encoded — see the `Color` doc on `a`), so a translucent emissive keeps its
alpha through the conversion.

## Where the pass is mounted (landed 2026-08-07)

**Bloom is one full-screen pass per *viewport*.** The `Environment` lives in
`ui/theme/default_game_env.tres` — one file, one dial, shared by every surface.

- **Root viewport:** the `WorldEnvironment` in `scenes/game_root.tscn`. All three
  level scenes inherit it from the composition root.
- **SubViewports** (the seven sandbox panels that render into their own `%World`)
  need **all three** of `own_world_3d = true`, `use_hdr_2d = true`, and a
  `WorldEnvironment` child. Copy any of them, or `gimbal_3d_showcase.tscn`.
- **Tuning surface:** the **Bloom** tab in the sandbox host
  (`addons/bloom_sandbox/`). Its sliders edit the shared resource *in place*, and
  its Save button writes it back — so tuning there is tuning the real dial.

### Three ways glow silently does nothing

All three fail with no error and no warning. In diagnosis order:

1. **`background_canvas_max_layer` defaults to `0`,** which excludes every
   `CanvasLayer` — i.e. the entire HUD. Set to `100`: verified to include the base
   canvas and layer 50, and to exclude layer 101 (`SceneTransition`'s black fade,
   which must never bloom).
2. **`use_hdr_2d` is per-viewport.** The `rendering/viewport/hdr_2d=true` project
   setting covers the **root viewport only**. A `SubViewport` defaults to `false`
   and renders inert no matter how correct its Environment is. Verified: own-world
   + HDR blooms, shared-world + HDR blooms, own-world *without* HDR does not.
3. **Without `own_world_3d`, a SubViewport's `WorldEnvironment` registers on the
   *shared* world.** In the editor that is the editor's own world — it collides
   with the editor's environment and leaks between panels. Glow still works; the
   damage is elsewhere.

Debug in that order, and **debug the Environment through the root viewport, never
through a SubViewport** — a SubViewport has two extra ways to render inert, so a
failure there tells you nothing about which of the three is wrong.

### `.tres` comments do not survive

The engine re-serializes an `Environment` `.tres` it touches and **strips every
`;` comment**. Rationale for a knob belongs here or in a rule file, never in the
resource. (General `.tres` hazards: `.claude/rules/godot-tres-authoring.md`.)

### Glow levels are the shape knob, not intensity

`glow_levels/1..7` are mip weights: level 1 is the tightest radius, 7 the widest.
With only 1–4 enabled (the obvious-looking default) glow pools **inside letter
counters and at stroke intersections** — it only accumulates where lit pixels are
already dense, which reads as grime rather than as light. Weighting outward
(`0.5 / 0.9 / 1.0 / 1.0 / 0.7 / 0.3`) gives a rim instead.

Judge that against **thin strokes**, not solid swatches. A 100×40 filled rect at
+3 blows out into a blob under settings that look right on text and rim arcs.

### Alpha is the fade channel; colour value is the dimmer

Canvas blending is non-premultiplied, so what reaches the pass is `rgb × a`. To
make something quieter, **drop a tier — don't drop alpha**. Alpha stays reserved
for animated reveals, where the bloom ramping in with the fade is a feature.

## See also

- `ui/theme/emissive.gd` — `Emissive.at(base, stops)` and the named tiers, the
  only sanctioned way to author an emissive colour in code.
- `theme.tres` — `TierInert` / `TierLabel` / `TierValue` / `TierAlert`
  `theme_type_variation`s, the way to author an emissive **Label**.
- #371 — the verdict this doc supports (bloom, not per-element SDF glow; the
  Layer 0/1/2 architecture; the Theme-resource palette home).
- `.claude/rules/rendering-performance.md` — bloom is a fullscreen pass; cost
  is fixed by resolution, independent of element count.
- `.claude/rules/godot-shaders.md` — headless import doesn't compile GLSL;
  verify under a real renderer.
- `.claude/rules/ui-palette.md` — the SDR palette this HDR layer rides atop.