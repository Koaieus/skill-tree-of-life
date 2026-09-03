@tool
# No class_name — consumers `preload` it as a const (`FloaterStyles`), which
# avoids a global_script_class_cache rebuild on import. Same trick as
# strikethrough_toast.gd; keeps this addable without disrupting an open editor.

## The named catalog of [FloaterStyle]s. Single source of truth for what a toast
## *looks like* per domain meaning: the [FloaterDirector] picks a style from here
## (which one is its discretion — see [method for_modifier]), and the toast
## sandbox enumerates [method gallery] to show every variant. Keeping both on the
## same factories is what stops the two from drifting.
##
## Every factory returns a FRESH [FloaterStyle] — callers may mutate freely, and
## no two toasts share style state.

## Domain colours (moved here from [FloaterDirector] so the palette lives with
## the styles that use it).
const COLOR_DAMAGE := Color(1.0, 0.25, 0.25, 1.0)
const COLOR_WOUND  := Color(1.0, 0.55, 0.55, 1.0)
const COLOR_HEAL   := Color(0.65, 1.0, 0.7, 1.0)
## Gold blended into a stat tint for the CORE-bound "build-defining" toast (#70).
const COLOR_MYTHIC := Color(1.0, 0.84, 0.3, 1.0)
## XP: a cooler, paler gold — reads as reward without competing with MYTHIC.
const COLOR_XP     := Color(1.0, 0.93, 0.62, 1.0)
## Crit: the damage hue itself, lifted over the bloom threshold rather than
## hue-shifted. A crit stays unambiguously DAMAGE-coloured — the intensity is
## carried by motion instead (see [method crit]).
const COLOR_CRIT := Color(1.0, 0.22, 0.22, 1.0)
## Denial: the register of [method SkillNode.shake_denied]'s tint, lifted a
## little for text legibility. Red-family like damage/wound — a refusal is bad
## news — but quiet: the [method denied] style stays default-size and unglowed.
const COLOR_DENIED := Color(1.0, 0.4, 0.4, 1.0)

const _CRIT_PUNCH_SCENE: PackedScene = preload(
		"res://ui/floating_number_layer/crit_punch_toast/crit_punch_toast.tscn")

const _STRIKETHROUGH_SCENE: PackedScene = preload(
		"res://ui/floating_number_layer/strikethrough_toast/strikethrough_toast.tscn")


# --- Discrete variants ------------------------------------------------------

## A plain filled number/text at [param color]. The workhorse basic style.
static func basic(color: Color) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = color
	return s


## The damage number. [param crit_tier] 0 is the workhorse flat red; >0 routes
## to whichever crit register [method crit] currently names.
static func damage(crit_tier: int = 0) -> FloaterStyle:
	if crit_tier > 0:
		return crit(crit_tier)
	return basic(COLOR_DAMAGE)


static func node_heal() -> FloaterStyle:
	return basic(COLOR_HEAL)


static func entity_wound() -> FloaterStyle:
	return basic(COLOR_WOUND)


static func entity_heal() -> FloaterStyle:
	return basic(COLOR_HEAL)


static func plain() -> FloaterStyle:
	return FloaterStyle.new()


## A gated verb's refusal — the "why" behind the denial buzz ([method
## SkillNode.shake_denied] says the click failed; this says why). Default size,
## no glow, and a SHORT hold: instructive, not alarming.
static func denied() -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = COLOR_DENIED
	s.float_time = 1.2
	return s


## A HUD-widget-targeted refusal (#743, [signal Events.ui_action_denied]) —
## same JOB as [method denied] (the "why" behind a refused click) but a louder
## register: full-saturation red, glowing, at [constant Emissive.ALERT]. The
## player directly clicked a widget and got turned away, which reads as more
## pointed than a board-side gate bump — [method denied]'s muted
## [constant COLOR_DENIED] tested too quiet for that. Per
## `.claude/rules/hdr-color.md` a glowing colour is always a named tier via
## [method Emissive.at], never a hand-picked float.
static func denied_alert() -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = Emissive.at(COLOR_DAMAGE, Emissive.ALERT)
	s.glow = true
	s.glow_color = s.fill_color
	s.float_time = 1.6
	return s


## XP gained — the reward register: gold and glowing, but smaller than a mythic
## modifier, because the per-turn income fires every single turn and must not
## shout as loud as a build-defining pickup.
static func xp_gain() -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = COLOR_XP
	s.glow = true
	s.glow_color = COLOR_XP
	s.font_size = 32
	return s


## A NODE-bound modifier gained — plain stat tint (#70/#82).
static func modifier_node(tint: Color) -> FloaterStyle:
	return basic(tint)


## A CORE-bound modifier gained — gold-blended, glowing, large: the mythic /
## build-defining register (#70).
static func modifier_core(tint: Color) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = tint.lerp(COLOR_MYTHIC, 0.6)
	s.glow = true
	s.font_size = 46
	s.float_time = 3.6
	return s


## A modifier removed — the strikethrough toast at original tint (the animation
## owns the desaturation, #82). Carries the concrete scene as [member
## FloaterStyle.scene_override].
static func modifier_removed(tint: Color) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = tint
	s.scene_override = _STRIKETHROUGH_SCENE
	return s


# --- Crit -------------------------------------------------------------------

## A critical hit. Emissive red — the damage hue lifted over the bloom
## threshold, NOT hue-shifted — with the intensity carried by MOTION: the number
## lands oversized and white-hot, snaps down on an overshoot, and cools into the
## red (see [CritPunchToast]'s scene script). Hence the [member
## FloaterStyle.scene_override]: entry animation is the one thing a style field
## cannot express, and it was the channel this layer was not using at all.
##
## [b]Hue is the weak signal here[/b] — a damage toast is already red, so a crit
## that only changes colour barely registers. Two alternatives were built and
## judged side by side in the toast sandbox before this one was picked; the
## rejected gold register is recorded in `.claude/rules/ui-palette.md`, not kept
## here as dead code.
##
## [param tier] is [member HitInstance.crit_tier]: 1 = a crit, >=2 = several crit
## sources stacked on one hit — the same field `ui/vfx/projectile/projectile.gd`
## escalates its `_on_crit` visual by, so the two cannot drift.
static func crit(tier: int = 1) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = Emissive.at(COLOR_CRIT, _crit_stops(tier))
	s.font_size = 44 + 4 * (maxi(tier, 1) - 1)
	s.float_time = 2.2
	s.scene_override = _CRIT_PUNCH_SCENE
	return s


## Extra EV a stacked crit earns over a single one, capped so a long crit chain
## can't drive the bloom pass into a white blob.
static func _crit_stops(tier: int) -> float:
	return minf(Emissive.VALUE + 0.5 * float(maxi(tier, 1) - 1), Emissive.ALERT)


# --- Semantic dispatch (the Director's discretion) --------------------------

## Per-variant modifier styling (#70/#82). Removed → strikethrough; CORE add →
## mythic; NODE add → plain tint. (#78 will refine the matrix further.)
static func for_modifier(
		tint: Color, binding: ModifierBinding.Kind, added: bool) -> FloaterStyle:
	if not added:
		return modifier_removed(tint)
	if binding == ModifierBinding.Kind.CORE:
		return modifier_core(tint)
	return modifier_node(tint)


# --- Gallery (the sandbox enumerates this) ----------------------------------

## Every distinct visual variant, as `{ name, text, style }` rows — what the toast
## sandbox iterates to build one +1/+3 button row per style. The modifier rows
## bake a representative tint so the sandbox needs no stat plumbing.
static func gallery() -> Array[Dictionary]:
	var mythic_tint := Color(0.55, 0.75, 1.0)  # a cool stat tint to show the gold blend
	return [
		{"name": "Damage",          "text": "7",           "style": damage()},
		{"name": "Crit",            "text": "18!",         "style": crit()},
		{"name": "Node heal",       "text": "+5",          "style": node_heal()},
		{"name": "Entity wound",    "text": "+1 WOUNDS",   "style": entity_wound()},
		{"name": "Entity heal",     "text": "-1 WOUNDS",   "style": entity_heal()},
		{"name": "Denied",          "text": "TOO FAR FROM CORE", "style": denied()},
		{"name": "Denied (alert)",  "text": "GEEN MANA MEER",   "style": denied_alert()},
		{"name": "Modifier (node)", "text": "+10 Strength","style": modifier_node(Color(0.9, 0.5, 0.4))},
		{"name": "Modifier (core)", "text": "+10 Strength","style": modifier_core(mythic_tint)},
		{"name": "Modifier removed","text": "+10 STR",     "style": modifier_removed(Color(0.9, 0.5, 0.4))},
		{"name": "XP gain",         "text": "+40 XP",      "style": xp_gain()},
		{"name": "Plain",           "text": "LEVEL UP",    "style": plain()},
	]
