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

const _STRIKETHROUGH_SCENE: PackedScene = preload(
		"res://ui/floating_number_layer/strikethrough_toast/strikethrough_toast.tscn")


# --- Discrete variants ------------------------------------------------------

## A plain filled number/text at [param color]. The workhorse basic style.
static func basic(color: Color) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = color
	return s


static func damage() -> FloaterStyle:
	return basic(COLOR_DAMAGE)


static func node_heal() -> FloaterStyle:
	return basic(COLOR_HEAL)


static func entity_wound() -> FloaterStyle:
	return basic(COLOR_WOUND)


static func entity_heal() -> FloaterStyle:
	return basic(COLOR_HEAL)


static func plain() -> FloaterStyle:
	return FloaterStyle.new()


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
		{"name": "Node heal",       "text": "+5",          "style": node_heal()},
		{"name": "Entity wound",    "text": "+1 WOUNDS",   "style": entity_wound()},
		{"name": "Entity heal",     "text": "-1 WOUNDS",   "style": entity_heal()},
		{"name": "Modifier (node)", "text": "+10 Strength","style": modifier_node(Color(0.9, 0.5, 0.4))},
		{"name": "Modifier (core)", "text": "+10 Strength","style": modifier_core(mythic_tint)},
		{"name": "Modifier removed","text": "+10 STR",     "style": modifier_removed(Color(0.9, 0.5, 0.4))},
		{"name": "XP gain",         "text": "+40 XP",      "style": xp_gain()},
		{"name": "Plain",           "text": "LEVEL UP",    "style": plain()},
	]
