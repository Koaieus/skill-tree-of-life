class_name IndicatorTheme
extends Resource

## Which [Indicator] scene a highlight role mounts. A role absent from a keyed
## theme falls to the overlay's [code]default_theme[/code] ([code]default.tres[/code],
## which maps every node role); absent from both, the node is unmarked.

@export var scenes: Dictionary[HighlightProvider.HighlightRole, PackedScene] = {}


func scene_for(role: HighlightProvider.HighlightRole) -> PackedScene:
	return scenes.get(role, null)
