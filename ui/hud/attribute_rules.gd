class_name AttributeRules
extends RefCounted
## Shared lookup for "what does this attribute drive" — used by the
## Attributes Panel's hover tooltip (#109) and intended for the Combat
## Readout's breakpoint slivers (#112).
##
## Owns NO prose (#289). Every entry's sentence is [method StatModifier.format]
## — the single home for modifier grammar (#305) — and its number is [method
## StatModifier.effective_value_text], the modifier's OWN live contribution
## (#791). The rules it reports are therefore DISCOVERED from the board's own
## `intrinsic_modifiers` (plus the entity's looted `core_modifiers`), not
## transcribed from them, which is what the old hardcoded `match` got wrong:
## it claimed "+1 / 10 STR" for blade size long after the formula moved to
## `/20`, and "+1 / decade of WIS" after XP regen moved to `/2`. A
## transcription drifts; a read can't.
##
## The number is this rule's contribution and never the target stat's total
## (#791 defect 3): "+1 Blade Size per 20 STR" next to a "3" that was the
## blade-size total from every source taught the player something false
## about where their numbers come from.

## One entry per leaf modifier driven by `attr_id`, in order: the board's
## `intrinsic_modifiers` first, then `core_modifiers` — the register a looted
## grant lands in when it does NOT merge into an intrinsic (a different
## divisor, #775); a merged one shows up on the intrinsic it merged into.
## Each entry is `{rule: String, contribution: String, stat_id: StringName}`:
## `rule` the normalised rate sentence (post-#891 a merged copy reads as one
## rate — "+1 XP / Turn per 3.75 WIS"), `contribution` what this rule adds
## right now through the [StatDef] value-type path ("+2", "+10%"), `stat_id`
## the target. Live values read off `board`. Unknown/undriven ids give [].
static func describe(attr_id: StringName, board: StatBoard,
		core_modifiers: Array[StatModifier] = []) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if board == null:
		return entries
	var leaves: Array[StatModifier] = StatModifier.flatten_all(board.intrinsic_modifiers)
	leaves.append_array(StatModifier.flatten_all(core_modifiers))
	for leaf in leaves:
		if not leaf.scales_with(attr_id):
			continue
		entries.append(_entry(leaf, board))
	return entries


static func _entry(m: StatModifier, board: StatBoard) -> Dictionary:
	return {
		"rule": m.format(),
		"contribution": m.effective_value_text(board),
		"stat_id": m.stat_id,
	}
