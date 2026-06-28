class_name FloaterStyle
extends Resource

## Declarative styling for one floater — the "advanced API" the [FloaterDirector]
## composes and hands (inside a [FloaterRequest]) to the renderer. Domain code
## never touches this. #78 owns what *values* express good/bad/neutral/rarity;
## this resource is just the carrier the renderer stamps onto a [Floater].

@export var fill_color: Color = Color.WHITE
@export var font_size: int = 36
## Signed drift along Y. Negative drifts *down* (the "lost / removed" register).
@export var float_distance: float = 70.0
@export var float_time: float = 3.0
@export_range(0, 90) var max_angle: int = 0
@export var glow: bool = false
@export var glow_color: Color = Color(1.0, 0.84, 0.3, 1.0)
## Optional exotic floater. MUST be an inherited scene from [Floater] (or a
## shared base) so the renderer drives it uniformly. Null → the stock Floater.
@export var scene_override: PackedScene = null


## Stamp these fields onto a freshly-instanced floater. One place owns the
## field copy so the renderer stays a dumb pump.
func apply_to(floater: Floater) -> void:
	floater.fill_color = fill_color
	floater.font_size = font_size
	floater.float_distance = float_distance
	floater.float_time = float_time
	floater.max_angle = max_angle
	floater.glow = glow
	floater.glow_color = glow_color
