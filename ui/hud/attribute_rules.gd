class_name AttributeRules
extends RefCounted
## Shared lookup for "what does this attribute drive" text — used by the
## Attributes Panel's hover tooltip (#109) and intended for the Combat
## Readout's breakpoint slivers (#112) so the STR->blade_size/etc. formula
## text isn't duplicated in two places. Mirrors the intrinsic table in
## .claude/rules/stats-system.md — update both if the intrinsics change.

## Returns one human-readable line per intrinsic driven by `attr_id`,
## reading live values off `board` (e.g. "STR -> Blade size +1/20 -> 3").
static func describe(attr_id: StringName, board: StatBoard) -> Array[String]:
	if board == null:
		return []
	match attr_id:
		&"strength":
			return [
				_line("Blade size", "+1 / 10 STR", board.blade_size),
				_line("Blade damage", "+1 / 10 STR", board.blade_damage),
			]
		&"dexterity":
			return [
				_line("Sensor range", "+1 hop / 10 DEX", board.sensor_range),
				_line("Firing range", "+1% / DEX", board.range),
			]
		&"intelligence":
			return [
				_line("Mana", "+1 / 10 INT", board.mana),
				_line("Mana regen", "+1 / decade of INT", board.mana_per_turn),
			]
		&"wisdom":
			return [_line("XP regen", "+1 / decade of WIS", board.xp_per_turn)]
		&"perception":
			return [_line("Vision range", "+2% / PER", board.vision_range)]
		_:
			return []


static func _line(target_label: String, rule: String, stat: Stat) -> String:
	if stat == null:
		return "%s -> %s" % [target_label, rule]
	return "%s -> %s -> %s" % [target_label, rule, str(stat.value)]
