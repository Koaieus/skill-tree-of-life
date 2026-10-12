class_name ReadoutLines
extends RefCounted

## Stub.


class ReadoutLine extends RefCounted:
	var aspect_id: StringName = &""
	var socket: int = -1
	var points: int = 0
	var innate: int = 0
	var infused: int = 0
	var per_hit: float = 0.0
	var status: StatusDef = null

	func exchange(_spell: SpellDef) -> String:
		return ""

	func text() -> String:
		return ""


static func lines(_plan: MagicAttackPlan) -> Array[ReadoutLine]:
	return []


static func preview(_plan: MagicAttackPlan, _socket: int, _aspect_id: StringName) -> Array[ReadoutLine]:
	return []
