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

## See also

- #371 — the verdict this doc supports (bloom, not per-element SDF glow; the
  Layer 0/1/2 architecture; the Theme-resource palette home).
- `.claude/rules/rendering-performance.md` — bloom is a fullscreen pass; cost
  is fixed by resolution, independent of element count.
- `.claude/rules/godot-shaders.md` — headless import doesn't compile GLSL;
  verify under a real renderer.
- `.claude/rules/ui-palette.md` — the SDR palette this HDR layer rides atop.