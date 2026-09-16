extends GutTest

## #289 — AttributeRules reports the board's ACTUAL intrinsics. The hardcoded
## `match` it replaced had drifted: it claimed "+1 / 10 STR" for blade size
## while the formula divided by 20, and "decade of WIS" for XP regen while the
## formula divided by 2. These tests read the shipped board, so a future
## divisor change either updates the text or fails here.

const BOARD := preload("res://entity/default_entity_board.tres")

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)
	_board.apply_intrinsics()


## The `rule` sentences of describe()'s structured entries (#791) — the
## half most of these tests care about.
func _lines(attr: StringName) -> Array[String]:
	var out: Array[String] = []
	for e in AttributeRules.describe(attr, _board):
		out.append(e.rule)
	return out


func _mk_ratio_mod(stat_id: StringName, source: StringName, divisor: float, val: float) -> StatModifier:
	var f := RatioFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = val
	m.formula = f
	return m


func test_null_board_is_empty() -> void:
	assert_eq(AttributeRules.describe(&"strength", null).size(), 0)


func test_unknown_attribute_is_empty() -> void:
	assert_eq(_lines(&"not_a_stat").size(), 0)


## The live RatioFormula divisor for `stat_id`'s intrinsic — read off the
## board rather than hardcoded, so a future owner retune (#776 already moved
## these once) doesn't repin a number here a second time.
func _ratio_divisor(stat_id: StringName) -> float:
	for m in _board.intrinsic_modifiers:
		if m.stat_id == stat_id and m.formula is RatioFormula:
			return (m.formula as RatioFormula).divisor
	fail_test("no RatioFormula intrinsic targets '%s'" % stat_id)
	return 0.0


static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return str(v)


func test_strength_lists_both_blade_rules_with_the_real_divisors() -> void:
	var lines := _lines(&"strength")
	assert_eq(lines.size(), 2, "blade damage + blade size")
	assert_string_contains(lines[0], "per %s STR" % _trim(_ratio_divisor(&"blade_damage")))
	assert_string_contains(lines[1], "per %s STR" % _trim(_ratio_divisor(&"blade_size")))


func test_wisdom_reports_the_current_xp_rule_not_the_retired_decade_one() -> void:
	var lines := _lines(&"wisdom")
	assert_eq(lines.size(), 1, "xp_per_turn only — sensor_range moved to perception")
	assert_string_contains(lines[0], "per %s WIS" % _trim(_ratio_divisor(&"xp_per_turn")))
	assert_false(lines[0].contains("decade"), "the decade rule is long gone")


func test_perception_line_carries_the_live_value() -> void:
	_board.perception.base_value = 30.0
	var entries := AttributeRules.describe(&"perception", _board)
	assert_eq(entries.size(), 2, "vision_range + sensor_range")
	assert_string_contains(entries[0].rule, "per PER")
	assert_eq(entries[0].stat_id, &"vision_range")
	var leaf: StatModifier = null
	for m in _board.intrinsic_modifiers:
		if m.stat_id == &"vision_range":
			leaf = m
	assert_not_null(leaf)
	assert_eq(entries[0].contribution, leaf.effective_value_text(_board),
			"this rule's own contribution, through the StatDef value-type path")
	assert_false(entries[0].rule.contains("->"), "no code arrow in player-facing copy")
	assert_false(entries[0].contribution.contains("->"))


# ── #791: structured entries — contribution is THIS rule's value, typed ─────

func test_contribution_is_the_rules_own_value_not_the_stat_total() -> void:
	# Hand-built rule (owner tunes the authored divisor; never pin it): +1 Blade
	# Size per 20 STR at STR 45 contributes floor(45/20) = 2 — regardless of
	# what the blade_size TOTAL is (its base plus every other source).
	var rule := _mk_ratio_mod(&"blade_size", &"strength", 20.0, 1.0)
	_board.intrinsic_modifiers = [rule] as Array[StatModifier]
	_board.strength.base_value = 45.0
	_board.blade_size.base_value = 7.0  # the total is NOT 2 — the old line printed this
	var entries := AttributeRules.describe(&"strength", _board)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].rule, rule.format())
	assert_eq(entries[0].contribution, "+2")
	assert_eq(entries[0].stat_id, &"blade_size")


func test_percent_typed_target_contribution_renders_with_a_percent_sign() -> void:
	var rule := _mk_ratio_mod(&"crit_chance", &"strength", 100.0, 0.05)
	_board.intrinsic_modifiers = [rule] as Array[StatModifier]
	_board.strength.base_value = 200.0
	var entries := AttributeRules.describe(&"strength", _board)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].contribution, "+10%")


func test_a_non_merging_looted_grant_is_its_own_row() -> void:
	# A looted copy with a DIFFERENT divisor does not merge (#775) and lands in
	# Entity.core_modifiers — describe() must list that bucket too.
	var entity := Entity.new()
	entity.stat_board = BOARD.duplicate(true) as EntityStatBoard
	entity.core_class = preload("res://entity/core/balanced_core.tres")
	add_child_autofree(entity)
	await get_tree().process_frame
	var board := entity.stat_board
	var before := AttributeRules.describe(&"wisdom", board, entity.core_modifiers).size()
	var loot := _mk_ratio_mod(&"xp_per_turn", &"wisdom", 1234.0, 1.0)  # mismatched divisor
	entity.absorb_core_modifier(loot)
	var entries := AttributeRules.describe(&"wisdom", board, entity.core_modifiers)
	assert_eq(entries.size(), before + 1, "the un-merged grant is its own row")
	assert_eq(entries[-1].rule, loot.format())
	assert_eq(entries[-1].contribution, loot.effective_value_text(board))


func test_perception_also_drives_sensor_range() -> void:
	var lines := _lines(&"perception")
	assert_string_contains(lines[1], "log(PER)")


func test_constitution_is_no_longer_blank() -> void:
	# The old `match` had no CON case at all (flagged in .claude/rules/stats-system.md).
	assert_gt(_lines(&"constitution").size(), 0, "CON drives node_health and health")


func test_intelligence_covers_mana_and_its_regen() -> void:
	# #766 made the innate INT->mana / INT->mana_per_turn scaling very
	# conservative (RatioFormula divisor 1000; the regen ladder starts three
	# decades later and no longer starts on its own common ratio, so its
	# clause is no longer "×10 INT" — see test_a_ladder_not_starting_at_its_
	# ratio_is_not_geometric). The rates are the owner's to retune; this
	# checks the readout still surfaces BOTH rules and that the max-mana one
	# still renders as a ratio ("per N INT"), without pinning N.
	var lines := _lines(&"intelligence")
	assert_gte(lines.size(), 2)
	var joined := "\n".join(lines)
	assert_string_contains(joined, "Max Mana")
	assert_string_contains(joined, "Mana / Turn")
	assert_string_contains(joined, " per ")
	assert_string_contains(joined, " INT")


func test_no_hardcoded_rule_strings_remain_in_the_source() -> void:
	# The docstring still QUOTES the old literals as the cautionary tale, so
	# this looks for the shapes that only a live lookup table would carry.
	var src := FileAccess.get_file_as_string("res://ui/hud/attribute_rules.gd")
	assert_false(src.contains("match attr_id"), "no per-attribute rule table")
	assert_false(src.contains("+1 hop / 10 DEX"), "no transcribed rule literals")
	assert_false(src.contains("+2% / PER"), "no transcribed rule literals")


# ── #791 / #792: a loot MERGE shows as one row at the merged rate ────────────

const _PANEL_SCENE := preload("res://ui/hud/attributes_panel/attributes_panel.tscn")
const _MOD_SLAB_ROW_SCENE := preload("res://ui/tooltip_fan/mod_slab_row.tscn")


func _spawn_entity() -> Entity:
	var entity := Entity.new()
	entity.stat_board = BOARD.duplicate(true) as EntityStatBoard
	entity.core_class = preload("res://entity/core/balanced_core.tres")
	add_child_autofree(entity)
	await get_tree().process_frame
	return entity


## The board's own intrinsic targeting `stat_id` — the merge target.
static func _intrinsic_of(board: StatBoard, stat_id: StringName) -> StatModifier:
	for m in board.intrinsic_modifiers:
		if m.stat_id == stat_id:
			return m
	return null


## A "t3 copy" of the intrinsic rule: same stat/op/formula (so it merges), a
## bigger coefficient. Duplicated off the board rather than hand-pinned so an
## owner retune of the divisor keeps the merge key matching.
static func _looted_copy_of(intrinsic: StatModifier, tier_value: float) -> StatModifier:
	var loot: StatModifier = intrinsic.duplicate(true)
	loot.value = tier_value
	return loot


func test_merged_loot_is_one_row_at_the_normalised_rate_on_every_surface() -> void:
	var entity := await _spawn_entity()
	var board := entity.stat_board
	var intrinsic := _intrinsic_of(board, &"xp_per_turn")
	assert_not_null(intrinsic, "sanity: WIS -> xp_per_turn is an authored intrinsic")
	var authored_value := intrinsic.value
	var before := AttributeRules.describe(&"wisdom", board, entity.core_modifiers)

	entity.absorb_core_modifier(_looted_copy_of(intrinsic, 3.0))

	var entries := AttributeRules.describe(&"wisdom", board, entity.core_modifiers)
	assert_eq(entries.size(), before.size(), "merged: no extra row")
	var xp_rows := entries.filter(func(e): return e.stat_id == &"xp_per_turn")
	assert_eq(xp_rows.size(), 1, "exactly one xp_per_turn row")
	assert_eq(intrinsic.value, authored_value + 3.0, "sanity: merged in place")
	assert_eq(xp_rows[0].rule, intrinsic.format(), "the normalised merged rate (#891)")
	assert_ne(xp_rows[0].rule, before[0].rule, "the rate moved")
	assert_eq(xp_rows[0].contribution, intrinsic.effective_value_text(board))

	# effect_readout_panel renders format_effective(board) of the same modifier.
	assert_string_contains(intrinsic.format_effective(board), intrinsic.effective_value_text(board))
	# mod_slab_row renders format() of the same modifier — one line at that rate.
	var slab = _MOD_SLAB_ROW_SCENE.instantiate()
	add_child_autofree(slab)
	slab.bind(intrinsic)
	assert_eq((slab.get_node("%Label") as Label).text, intrinsic.format())


# ── #791 acceptance 4: an open tooltip rebuilds when a merge lands ──────────

func _tooltip_rows(panel: AttributesPanel) -> Array:
	return panel.get_node("%TooltipRows").get_children().filter(func(c): return c.visible)


func test_open_tooltip_updates_when_a_merge_lands_without_rehover() -> void:
	var entity := await _spawn_entity()
	var panel: AttributesPanel = _PANEL_SCENE.instantiate()
	add_child_autofree(panel)
	panel.bind(entity.stat_board, entity.core_modifiers)
	var intrinsic := _intrinsic_of(entity.stat_board, &"blade_size")
	assert_not_null(intrinsic)

	panel._on_row_hovered(&"strength")
	assert_true(panel.get_node("%Tooltip").visible)
	var rows := _tooltip_rows(panel)
	assert_eq(rows.size(), 2, "blade damage + blade size")
	var size_row = rows.filter(func(r): return r.stat_id == &"blade_size")[0]
	assert_eq(size_row.rule, intrinsic.format())

	entity.absorb_core_modifier(_looted_copy_of(intrinsic, 3.0))

	rows = _tooltip_rows(panel)
	assert_eq(rows.size(), 2, "still one row per rule")
	size_row = rows.filter(func(r): return r.stat_id == &"blade_size")[0]
	assert_eq(size_row.rule, intrinsic.format(), "rebuilt to the merged rate while shown")
	assert_eq(size_row.contribution, intrinsic.effective_value_text(entity.stat_board))
	assert_false(size_row.rule.contains("->"))


## Developer-facing dumps under ui/ that legitimately write a code arrow —
## never rendered to a player. Add to this list only with the same argument.
const _DEBUG_DUMPS_NOT_COPY: Array[String] = [
	"res://ui/hud/minimap_panel/minimap_viewport_rect_layer.gd",  # describe_coverage() diagnostic
]


func test_no_code_arrow_in_player_facing_ui_strings() -> void:
	var offenders: Array[String] = []
	_scan_for_arrow("res://ui", offenders)
	offenders = offenders.filter(func(o: String) -> bool:
		return not _DEBUG_DUMPS_NOT_COPY.any(func(d: String) -> bool: return o.begins_with(d)))
	assert_eq(offenders, [] as Array[String], "'->' in a string literal under ui/: %s" % str(offenders))


static func _scan_for_arrow(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_for_arrow(path, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var line := lines[i].strip_edges()
				if line.begins_with("#") or line.begins_with("##"):
					continue
				# A '->' inside a quoted string is player-facing copy; the GDScript
				# return-type arrow sits outside any quotes.
				var re := RegEx.create_from_string("\"[^\"]*->[^\"]*\"")
				if re.search(line) != null:
					out.append("%s:%d" % [path, i + 1])
		name = dir.get_next()
	dir.list_dir_end()
