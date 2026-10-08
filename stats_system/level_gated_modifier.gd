class_name LevelGatedModifier
extends StatModifier

## A modifier that appears at allocation level [member unlock_level]: below it
## the modifier is its operation's neutral element (0, or 1.0 for MULTIPLY);
## at or above it, it carries the authored value outright and does not ladder
## further. Rides the [method _local_scale_override] seam, so the board path
## and the off-board `scaled_copy` path both gate with no change.
##
## The mutator overwrites `value` as the node's level moves, so the authored
## number is captured once, before the first scale, and every later answer is
## derived from it — 1→3→1→3 never drifts. SET is out of scope.

## Allocation level (the A of A/B) at which the authored value appears.
@export_range(1, 8, 1, "or_greater") var unlock_level: int = 3

## The authored `value`, captured on the first scale. NAN = not captured yet.
@export_storage var _authored: float = NAN


func _local_scale_override(_old_al: int, new_al: int) -> Variant:
	if operation == Operation.SET:
		push_warning("LevelGatedModifier: SET is not supported (stat '%s')" % stat_id)
		return null
	if is_nan(_authored):
		_authored = value
	return _authored if new_al >= unlock_level else _neutral()


func _neutral() -> float:
	return 1.0 if operation == Operation.MULTIPLY else 0.0


## The authored value, as the description should read it: captured if the
## mutator has run, else the live `value`.
func _shown_value() -> float:
	return value if is_nan(_authored) else _authored


func format() -> String:
	var parts := _display_parts()
	return "%s at %d/X" % [_format_value(parts[0], parts[1], parts[2], _shown_value()), unlock_level]
