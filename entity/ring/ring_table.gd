class_name RingTable
extends RefCounted


class Cell extends RefCounted:
	var name: StringName
	var aspect: Resource  ## an [Aspect]; null on a keystone
	var sector: Identity
	var tier: int
	var cost: int
	var grants: Array[StatModifier] = []
	var neighbours: Array[StringName] = []


func can_buy(_spent: Array[StringName], _cell: StringName) -> bool:
	return false


func cells() -> Array[StringName]:
	return []


func cell(_name: StringName) -> Cell:
	return null
