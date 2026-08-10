@tool
class_name SpellGrantPoolEntry
extends Resource

## One pick option in a [SpellGrantPool]. `weight` is the sampling weight —
## the whole knob for v1 (no archetype/band/tier modulation yet, see #248).

@export var spell_def: SpellDef
@export var weight: float = 1.0


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if spell_def == null:
		out.append("spell_def is null — entry will never be picked.")
	if weight <= 0.0:
		out.append("weight should be > 0.")
	return out
