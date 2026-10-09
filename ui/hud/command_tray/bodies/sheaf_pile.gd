@tool
class_name SheafPile
extends Control

## A stockpile drawn as sheaf tiers: singles, tied bundles, sheaves, then `+`.

const PLUS := -1

@export var count: int = 0
@export var tint: Color = Color.WHITE
@export var tier_sizes: PackedInt32Array = [1, 5, 25]
@export var max_marks: int = 5


## The tier index per mark, largest first; [constant PLUS] closes an overflow.
static func marks(_count: int, _tier_sizes: PackedInt32Array, _max_marks: int) -> Array[int]:
	return []
