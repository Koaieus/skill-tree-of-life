class_name FloaterStyle
extends Resource

## Declarative styling for one floater — the "advanced API" the [FloaterDirector]
## composes and hands (inside a [FloaterRequest]) to the renderer. Domain code
## never touches this. #78 owns what *values* express good/bad/neutral/rarity;
## this resource is just the carrier the renderer stamps onto a [Floater].

@export var fill_color: Color = Color.WHITE
## Font size override. 0 = inherit the toast scene's authored size (the common
## case — basic damage/heal toasts leave this unset). >0 overrides it, e.g. the
## mythic CORE-modifier toast at 46 (#70).
@export var font_size: int = 0
## On-screen hold override. 0 = inherit the toast scene's authored
## [member FloaterToast.visible_duration]. >0 overrides it (e.g. the mythic toast
## lingers at 3.6s for a build-defining beat).
@export var float_time: float = 0.0
@export var glow: bool = false
@export var glow_color: Color = Color(1.0, 0.84, 0.3, 1.0)
## Optional concrete toast scene. MUST be a scene whose root extends [FloaterToast]
## so [FloaterToaster] can call [method FloaterToast.set_content] and
## [method FloaterToast.animate] on it. Null → the stock [FloaterToast].
## Used by [FloaterDirector] to swap in specialised toast variants — e.g. the
## strikethrough scene for removed modifiers (#82).
@export var scene_override: PackedScene = null
