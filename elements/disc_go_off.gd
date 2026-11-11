@tool
class_name DiscGoOff
extends GoOff

## Stub (#1799 D, red first).

enum Power { EXPLOSIVE_CHARGES }
enum Radius { EXPLOSIVE_SPREAD }

@export var power_source := Power.EXPLOSIVE_CHARGES
@export var radius_source := Radius.EXPLOSIVE_SPREAD


static func spend_of(_load: int, _present: int) -> int:
	return -1


static func power_of(_load: int, _present: int, _resonance: int) -> int:
	return -1


static func present_on(_slice: NodeCombat) -> Array:
	return [null, 0.0]


func power_at(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> int:
	return 0


func spend_at(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> int:
	return 0


func radius_at(_node: SkillNode, _power: int) -> float:
	return 0.0
