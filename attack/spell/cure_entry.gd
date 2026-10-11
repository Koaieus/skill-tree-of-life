@tool
class_name CureEntry
extends Resource

## One row of a [Cure] table: which status it clears and at what price.

## The status this row clears.
@export var status: StatusDef = null

## Stacks cleared per unit of dose — 1.0 costs one dose a stack, 0.5 costs two.
## Authored per entry; the defaults belong to the spell's table.
@export_range(0.05, 4.0, 0.05) var rate: float = 1.0
