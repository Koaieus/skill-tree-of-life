@tool
class_name CollisionProfile
extends WeightProfile

## Zeroes weight for any entry whose `(stat_id, operation)` pair already
## appears in `context.already_rolled`. Enforces the "no `+1 STR | +2 STR`"
## rule from docs/domain/procgen-v2.md — re-rolls pick a different (stat, op)
## pair instead of fusing or duplicating.
##
## Profile is stateless; no exports.

func multiplier_for(entry: ModifierPoolEntry, context: WeightContext) -> float:
	if entry == null or context == null or context.already_rolled.is_empty():
		return 1.0
	for m in context.already_rolled:
		if m == null:
			continue
		if m.stat_id == entry.stat_id and m.operation == entry.operation:
			return 0.0
	return 1.0
