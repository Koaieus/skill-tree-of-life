@tool
class_name StatModifierDef
extends Resource

## The designer-loop atom: pick a stat (by id), pick an op, enter a value.
## Sat on a SkillNode's `modifiers: Array[StatModifierDef]`.
## Application order at runtime: ADD_FLAT → ADD_PERCENT → MULTIPLY (PoE-style).

enum Operation { ADD_FLAT, ADD_PERCENT, MULTIPLY, SET }

@export var stat_id: StringName = &""
@export var operation: Operation = Operation.ADD_FLAT
@export var value: float = 0.0
