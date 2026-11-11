@tool
class_name GoOff
extends Resource

## Abstract: what a primed node does when a hit sets it off — the element's
## reach. Stub (#1798 red test first).

@export_range(0.0, 1.0, 0.05) var share := 1.0
@export var lands_on_own_node := true


func fire(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> GoOffResult:
	return GoOffResult.new()


func _reach(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> Array[GoOffResult.Reach]:
	var out: Array[GoOffResult.Reach] = []
	return out
