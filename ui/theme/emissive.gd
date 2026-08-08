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
