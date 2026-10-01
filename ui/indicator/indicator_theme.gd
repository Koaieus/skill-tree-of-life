class_name IndicatorTheme
extends Resource

## Which [Indicator] scene a highlight role mounts. A role absent from
## [member scenes] keeps the overlay's plain ring — the map is the only switch.

@export var scenes: Dictionary[HighlightProvider.HighlightRole, PackedScene] = {}


func scene_for(role: HighlightProvider.HighlightRole) -> PackedScene:
	return scenes.get(role, null)
