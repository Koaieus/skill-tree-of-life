class_name AttributeRules
extends RefCounted
## Shared lookup for "what does this attribute drive" text — used by the
## Attributes Panel's hover tooltip (#109) and intended for the Combat
## Readout's breakpoint slivers (#112).
##
## Owns NO prose (#289). Every line is [method StatModifier.format] — the
## single home for modifier grammar (#305) — plus the target stat's live
## value. The rules it reports are therefore DISCOVERED from the board's own
## `intrinsic_modifiers`, not transcribed from them, which is what the old
## hardcoded `match` got wrong: it claimed "+1 / 10 STR" for blade size long
## after the formula moved to `/20`, and "+1 / decade of WIS" after XP regen
## moved to `/2`. A transcription drifts; a read can't.

## Returns one line per intrinsic modifier driven by `attr_id`, reading live
## values off `board` — e.g. "+1 Blade Size per 20 STR -> 3". Order follows
## the board's `intrinsic_modifiers` array. Unknown/undriven ids give [].
static func describe(attr_id: StringName, board: StatBoard) -> Array[String]:
	var lines: Array[String] = []
	if board == null:
		return lines
	for leaf in StatModifier.flatten_all(board.intrinsic_modifiers):
		if not leaf.scales_with(attr_id):
			continue
		lines.append(_line(leaf, board.get_stat(leaf.stat_id)))
	return lines


## "<sentence> -> <live value>". The sentence already names the target stat
## (format() includes it), so there's no separate label column any more — the
## live value is the only thing the modifier can't say about itself.
static func _line(m: StatModifier, stat: Stat) -> String:
	if stat == null:
		return m.format()
	return "%s -> %s" % [m.format(), str(stat.value)]
