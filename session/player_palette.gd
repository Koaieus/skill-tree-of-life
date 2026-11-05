@tool
class_name PlayerPalette
extends Resource

## The colours a lobby slot may pick a hero from, authored once as
## `session/player_palette.tres`. Distinct from the stat palette (identity, not
## stat). Gold and pure white are deliberately absent; sixteen OKLCH-derived
## colours in two tiers. `default_for` walks the array round-robin.
## See docs/domain/lobby.md

## Every colour a slot may choose, in picker order.
@export var colors: Array[Color] = []


func size() -> int:
	return colors.size()


## The default colour for the slot at [param index], wrapping if a roster ever
## outgrows the palette. Max roster today is 6 (2 humans + 4 AI); sixteen
## entries is headroom, not a coincidence — the first eight are the whole
## tier a roster ever actually draws from by default.
func default_for(index: int) -> Color:
	if colors.is_empty():
		return Color.WHITE
	return colors[index % colors.size()]


## Does this palette offer [param color]? Compared exactly — every colour that
## reaches here came out of this same array, so no epsilon is warranted and an
## epsilon would blur two neighbouring entries into one.
func has_color(color: Color) -> bool:
	return colors.has(color)
