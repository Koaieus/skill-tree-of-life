extends GutTest

## #825 — a `StatDef.description`'s "+N per D <STAT>" prose must agree with the
## live `RatioFormula.divisor` actually driving that stat, on every shipped
## board. `blade_size.tres` drifted to "/10" while the formula moved to "/20"
## (#771 sized the AI's blade budget off the stale prose, 2x optimistic).
##
## Divisors are owner-tuned and will move again (#776), so this reads the
## divisor off the formula and the ratio off the description — never a
## literal — and goes red only on real drift, never on a retune. A def whose
## description carries no "per N <STAT>" phrase is skipped, not failed: not
## every stat spells its ratio out in prose (xp_per_turn, spell_range).

const BOARD := preload("res://entity/default_entity_board.tres")
const BLOCKER_SMALL := preload("res://entity/blocker/blocker_small_board.tres")
const BLOCKER_MEDIUM := preload("res://entity/blocker/blocker_medium_board.tres")
const BLOCKER_LARGE := preload("res://entity/blocker/blocker_large_board.tres")


## Pulls the first "per <number> <ABBR>" phrase out of a description, anchored
## on the source stat's own abbreviation so "per 10 STR" in a STR-sourced
## formula's target never matches a DEX or INT phrase in the same sentence.
## Returns null (not 0.0) when no such phrase is authored — the "skip, don't
## fail" case the brief calls out.
func _ratio_in_description(description: String, abbrev: String) -> Variant:
	var re := RegEx.new()
	re.compile("(?i)per\\s+([0-9]+(?:\\.[0-9]+)?)\\s+%s\\b" % abbrev)
	var m := re.search(description)
	if m == null:
		return null
	return float(m.get_string(1))


func _assert_ratio_descriptions_agree(board: EntityStatBoard, where: String) -> void:
	for leaf in StatModifier.flatten_all(board.intrinsic_modifiers):
		if not (leaf.formula is RatioFormula):
			continue
		var formula := leaf.formula as RatioFormula

		var target_def := StatRegistry.get_def(leaf.stat_id)
		assert_not_null(target_def, "%s: no StatDef for target '%s'" % [where, leaf.stat_id])
		if target_def == null:
			continue

		var source_id := StatFormula.base_of(formula.source_stat_id)
		var source_def := StatRegistry.get_def(source_id)
		assert_not_null(source_def, "%s: no StatDef for source '%s'" % [where, source_id])
		if source_def == null:
			continue

		var described: Variant = _ratio_in_description(target_def.description, source_def.get_abbrev())
		if described == null:
			continue  # no ratio phrase authored on this def — nothing to agree on

		assert_eq(
			described, formula.divisor,
			(
				"%s: %s's description says 'per %s %s' but the live formula divides by %s"
				% [where, leaf.stat_id, described, source_def.get_abbrev(), formula.divisor]
			)
		)


func test_default_board_ratio_descriptions_agree_with_their_formulas() -> void:
	_assert_ratio_descriptions_agree(BOARD, "default_entity_board")


func test_blocker_boards_ratio_descriptions_agree_with_their_formulas() -> void:
	_assert_ratio_descriptions_agree(BLOCKER_SMALL, "blocker_small_board")
	_assert_ratio_descriptions_agree(BLOCKER_MEDIUM, "blocker_medium_board")
	_assert_ratio_descriptions_agree(BLOCKER_LARGE, "blocker_large_board")
