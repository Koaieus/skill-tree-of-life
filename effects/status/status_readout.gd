class_name StatusReadout
extends RefCounted

## STUB — replaced by the real rule.
static func shown_power(row: NodeStatus, _viewers: Array[Entity]) -> int:
	return row.power


static func shown_normalised(row: NodeStatus, _viewers: Array[Entity]) -> float:
	return row.normalised()
