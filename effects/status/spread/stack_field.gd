class_name StackField
extends RefCounted

## STUB
var def: StatusDef
var mask: int = 2


func _init(p_def: StatusDef = null, p_mask: int = 2, p_adjacency: Dictionary = {}) -> void:
	def = p_def
	mask = p_mask


func stacks(_n: NodeCombat) -> float:
	return 0.0


func masked_neighbours(_n: NodeCombat) -> Array[NodeCombat]:
	return [] as Array[NodeCombat]
