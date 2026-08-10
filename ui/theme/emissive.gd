@tool
class_name Emissive
extends RefCounted
## HDR colour authoring for the bloom pass (#371) — the tier vocabulary in code.
##
## A thing glows iff its composited pixel exceeds the Environment's
## `glow_hdr_threshold` (1.0) in LINEAR space. Nothing in `Color` records "this is
## emissive"; the rgb channels are just floats above 1.0. So the whole discipline
## is: never hand-pick a float, always name a **tier** — see
## `docs/domain/hdr-color.md` for the derivation and the empirical stop table.
##
## Two homes, one vocabulary:
##   - **Text** goes through `theme_type_variation` on `theme.tres`
##     (`TierLabel` / `TierValue` / `TierAlert`) — an inspector dropdown, so a
##     scene cannot drift off-palette without visibly choosing to.
##   - **Everything a Theme cannot reach** — shader glow terms, `modulate`,
##     `INSTANCE_CUSTOM`, `Gradient` stops, particle colours — comes through here.
##
## Per `.claude/rules/ui-palette.md`, `StatDef.tint_color` remains the single
## source of truth for stat and vital colours. The emissive layer for those is
## `Emissive.at(stat_def.tint_color, Emissive.VALUE)` — **never** a parallel table
## of HDR stat colours.

## Tier stops, in EV. +1 stop = ×2 linear. Named because the ONLY sanctioned way
## to author an emissive colour is `Emissive.at(base, <one of these>)`.
const INERT := 0.0    ## Sits exactly at threshold: visible, never blooms.
const LABEL := 0.5    ## A whisper — supporting text, idle borders.
const VALUE := 1.0    ## The default "this is lit" reading. Numbers, active state.
const ALERT := 2.0    ## Full neon. Reserve it, or nothing reads as loud.
const PEAK := 3.0     ## A momentary overshoot above ALERT — an ignition flash
					   ## relaxing back down, never a resting state.

## Neutral base for untinted emissive content — the Arcane Terminal off-white
## (CON's `oklch(0.92 0.02 250)`, per `.claude/rules/ui-palette.md`). Anything with
## its own identity colour should pass that instead.
const NEUTRAL := Color(0.8586, 0.9018, 0.9482)


## Raise `base` by `stops` EV and return the sRGB-encoded result.
##
## Uses the engine's own conversions — the same code path `ColorPicker`'s `I`
## slider takes — so a value produced here is byte-identical to one authored by
## dragging that slider to the same stop. Alpha is carried through untouched:
## `srgb_to_linear()` leaves `a` alone (alpha is always stored linear), and the
## explicit restore below keeps that true if that ever changes upstream.
##
## Caveat worth budgeting for: canvas blending is non-premultiplied, so what
## actually reaches the bloom pass is `rgb × a`. A translucent emissive element
## emits proportionally less. Hence the house rule — **alpha is the fade channel,
## colour value is the dimmer.** To make something quieter, drop a tier; don't
## drop alpha.
static func at(base: Color, stops: float) -> Color:
	var lin := base.srgb_to_linear() * pow(2.0, stops)
	lin.a = base.a
	return lin.linear_to_srgb()


## `at()` against the neutral off-white, for content with no identity colour.
static func neutral(stops: float) -> Color:
	return at(NEUTRAL, stops)


## Rec.709 luma weights — how much each linear channel contributes to
## perceived/bloom-extracted brightness. Blue is heavily discounted (0.0722)
## relative to green (0.7152); a blue-dominant hue (e.g. INT's tint) can sit
## at max channel value and still read as dim to the glow pass.
const _LUMA := Vector3(0.2126, 0.7152, 0.0722)

## Like [method at], but first rescales `base` so its Rec.709 luminance is 1.0
## — i.e. strips out how bright/dark the identity colour *itself* happens to
## be, keeping only its hue/chroma, before applying the stop lift.
##
## Use this for a hot/glow term driven by an arbitrary identity colour (a stat
## or archetype tint) where equal `stops` should read as equal glow across
## different hues. [method at] does not do this — two colours with the same
## channel values but different luminance (e.g. a saturated blue vs a
## saturated red) bloom by very different amounts at the same stop count,
## because bloom thresholds per channel and blue is discounted 10x against
## green. Confirmed empirically 2026-08-08 tuning `Edge`/`SlabPanel`: a
## STR-red archetype tint (linear luminance ≈0.23) and an INT-blue one
## (≈0.31) needed visibly different raw stops to "properly bloom" even though
## both stayed the same nominal tier. See docs/domain/hdr-color.md.
##
## `tint(Color.WHITE, stops) == at(Color.WHITE, stops)` exactly — white's own
## luminance is already 1.0, so there is nothing to rescale. And at `stops =
## 0` any hue lands at luminance 1.0 (linear) — the [constant INERT]
## definition, generalised from "white sits at threshold" to "any colour's
## luminance sits at threshold."
##
## A fully black `base` (luminance 0) has no hue to preserve; falls back to
## [method at] rather than dividing by zero.
static func tint(base: Color, stops: float) -> Color:
	var lin := base.srgb_to_linear()
	var luminance := lin.r * _LUMA.x + lin.g * _LUMA.y + lin.b * _LUMA.z
	if luminance <= 0.0001:
		return at(base, stops)
	var factor := pow(2.0, stops) / luminance
	var out := Color(lin.r * factor, lin.g * factor, lin.b * factor, base.a)
	return out.linear_to_srgb()


## CANDIDATE, not yet adopted anywhere — compare live against [method tint] in
## `dev_bloom_sandbox`'s archetype-equalization band before reaching for this.
##
## [method tint] equalizes the weighted-luminance value bloom's bright-pass
## GATES on, but the blur/composite that follows runs on raw per-channel
## values, not on a re-collapsed luminance scalar — so two hues at equal
## `tint()`-luminance can still carry very different raw channel magnitudes
## into the blur. A saturated blue's channel has to swell ~14x to reach a
## given luminance (blue's Rec.709 weight is only 0.0722); a saturated
## green's only needs ~1.4x (weight 0.7152) — same nominal "stops", very
## different raw energy feeding bloom. `tint_peak()` normalizes by the base's
## PEAK channel instead, so every hue's dominant channel lands at the same
## absolute value — closer to what the blur actually sums, at the cost of no
## longer landing on the named stop's nominal luminance.
static func tint_peak(base: Color, stops: float) -> Color:
	var lin := base.srgb_to_linear()
	var peak: float = maxf(lin.r, maxf(lin.g, lin.b))
	if peak <= 0.0001:
		return at(base, stops)
	var factor := pow(2.0, stops) / peak
	var out := Color(lin.r * factor, lin.g * factor, lin.b * factor, base.a)
	return out.linear_to_srgb()


## CANDIDATE, not yet adopted anywhere — see [method tint_peak]'s caveat, same
## "compare live before adopting" rule applies.
##
## A midpoint between [method at] (no correction at all — low-luminance hues
## under-bloom) and [method tint] (full luminance correction — low-luminance
## hues can over-bloom once the raw-channel gap above is accounted for).
## Applies the luminance-ratio correction at HALF strength (square root) —
## `factor = pow(2, stops) / sqrt(luminance)` — rather than the full inverse,
## so the correction pulls low-luminance hues up without swinging as far past
## high-luminance ones.
static func tint_damped(base: Color, stops: float) -> Color:
	var lin := base.srgb_to_linear()
	var luminance := lin.r * _LUMA.x + lin.g * _LUMA.y + lin.b * _LUMA.z
	if luminance <= 0.0001:
		return at(base, stops)
	var factor := pow(2.0, stops) / sqrt(luminance)
	var out := Color(lin.r * factor, lin.g * factor, lin.b * factor, base.a)
	return out.linear_to_srgb()
