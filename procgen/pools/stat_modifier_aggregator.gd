class_name StatModifierAggregator
extends RefCounted

## Stub (#730 red): signatures only.

class Group extends RefCounted:
	var mod: StatModifier
	var cost: int
	var entries: Array[ModifierPoolEntry] = []

var _groups: Dictionary[StringName, Group] = {}


static func key_of(_mod: StatModifier) -> StringName:
	return &""


func append(_mod: StatModifier, _cost: int, _entry: ModifierPoolEntry) -> void:
	pass


func get_aggregate() -> Array[StatModifier]:
	return []


func entries_for(_mod: StatModifier) -> Array[ModifierPoolEntry]:
	return []


static func merge_into(a: StatModifier, _b: StatModifier) -> StatModifier:
	return a


static func reroll_into(_mod: StatModifier, _group: Array, _rng: RandomNumberGenerator) -> void:
	pass
