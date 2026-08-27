extends GutTest

## #305 — StatModifier.format() is the single shared home for the
## modifier-to-sentence grammar (full sentence, stat name included).

func _mod(stat_id: StringName, op: StatModifier.Operation, val: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = val
	return m


# --- All five operators on a plain stat (StatDef.display_name, no modifier_name) --

func test_add_base_plain_stat() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.ADD_BASE, 4.0).format(), "+4 Strength")


func test_increase_plain_stat() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.INCREASE, 18.0).format(), "+18% increased Strength")


func test_multiply_plain_stat() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.MULTIPLY, 1.3).format(), "×1.3 Strength")


func test_add_bonus_plain_stat() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.ADD_BONUS, 3.0).format(), "+3 bonus Strength")


func test_set_plain_stat() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.SET, 3.0).format(), "Strength is 3")


func test_negative_value_keeps_own_sign() -> void:
	assert_eq(_mod(&"strength", StatModifier.Operation.ADD_BASE, -5.0).format(), "-5 Strength")


# --- #622: value_type-aware formatting — FLOAT keeps decimals, INT still rounds ---

func test_add_base_on_a_float_stat_keeps_decimals() -> void:
	# crit_multiplier is FLOAT-typed with no display_as_percent — the root-cause
	# case: _format_value used to blanket-roundi() this to "+2 Crit Multiplier".
	assert_eq(
		_mod(&"crit_multiplier", StatModifier.Operation.ADD_BASE, 1.5).format(),
		"+1.5 Crit Multiplier"
	)


func test_increase_on_a_float_stat_keeps_decimals() -> void:
	assert_eq(
		_mod(&"crit_multiplier", StatModifier.Operation.INCREASE, 1.5).format(),
		"+1.5% increased Crit Multiplier"
	)


func test_add_bonus_on_a_float_stat_keeps_decimals() -> void:
	assert_eq(
		_mod(&"crit_multiplier", StatModifier.Operation.ADD_BONUS, 1.5).format(),
		"+1.5 bonus Crit Multiplier"
	)


func test_add_base_on_an_int_stat_still_rounds() -> void:
	# strength is INT-typed — unaffected by #622's fix, pinned so a future
	# regression on the type-aware branch shows up here too.
	assert_eq(
		_mod(&"strength", StatModifier.Operation.ADD_BASE, 4.6).format(),
		"+5 Strength"
	)


# --- modifier_name substitution on a pool stat, across all five operators ---------

func test_add_base_modifier_name_substitution() -> void:
	assert_eq(
		_mod(&"action_points", StatModifier.Operation.ADD_BASE, 4.0).format(),
		"+4 Max Action Points"
	)


func test_increase_modifier_name_substitution() -> void:
	assert_eq(
		_mod(&"mana", StatModifier.Operation.INCREASE, 18.0).format(),
		"+18% increased Max Mana"
	)


func test_multiply_modifier_name_substitution() -> void:
	assert_eq(
		_mod(&"action_points", StatModifier.Operation.MULTIPLY, 1.5).format(),
		"×1.5 Max Action Points"
	)


func test_add_bonus_modifier_name_substitution() -> void:
	assert_eq(
		_mod(&"action_points", StatModifier.Operation.ADD_BONUS, 2.0).format(),
		"+2 bonus Max Action Points"
	)


func test_set_modifier_name_substitution() -> void:
	assert_eq(
		_mod(&"action_points", StatModifier.Operation.SET, 3.0).format(),
		"Max Action Points is 3"
	)


# --- display_as_percent on crit_chance: ADD_BASE / ADD_BONUS / SET scaled ---------

func test_display_as_percent_add_base() -> void:
	assert_eq(
		_mod(&"crit_chance", StatModifier.Operation.ADD_BASE, 0.05).format(),
		"+5% Crit Chance"
	)


func test_display_as_percent_add_bonus() -> void:
	assert_eq(
		_mod(&"crit_chance", StatModifier.Operation.ADD_BONUS, 0.05).format(),
		"+5% bonus Crit Chance"
	)


func test_display_as_percent_set() -> void:
	assert_eq(
		_mod(&"crit_chance", StatModifier.Operation.SET, 0.10).format(),
		"Crit Chance is 10%"
	)


## INCREASE / MULTIPLY are NOT scaled by display_as_percent — their values are
## already percent-points / raw multipliers, not quantities in the stat's units.

func test_display_as_percent_increase_is_unscaled() -> void:
	assert_eq(
		_mod(&"crit_chance", StatModifier.Operation.INCREASE, 18.0).format(),
		"+18% increased Crit Chance"
	)


func test_display_as_percent_multiply_is_unscaled() -> void:
	assert_eq(
		_mod(&"crit_chance", StatModifier.Operation.MULTIPLY, 1.3).format(),
		"×1.3 Crit Chance"
	)


# --- CompositeStatModifier.format() joins with ", " ------------------------------

func test_composite_format_joins_with_comma_space() -> void:
	var a := _mod(&"action_points", StatModifier.Operation.ADD_BASE, 2.0)
	var b := _mod(&"skill_points", StatModifier.Operation.ADD_BASE, -1.0)
	var c := CompositeStatModifier.new()
	c.children = [a, b]
	assert_eq(c.format(), "+2 Max Action Points, -1 Max Skill Points")


# --- format() fallback when StatRegistry.get_def() returns null ------------------

func test_format_fallback_when_def_missing() -> void:
	assert_eq(
		_mod(&"totally_unregistered_stat_id", StatModifier.Operation.ADD_BASE, 4.0).format(),
		"+4 totally_unregistered_stat_id"
	)


# --- tint audit: every StatDef in stats_system/defs/ has a non-white tint --------

func test_every_stat_def_has_non_white_tint() -> void:
	var dir := DirAccess.open("res://stats_system/defs")
	assert_not_null(dir, "stats_system/defs must be readable")
	dir.list_dir_begin()
	var file := dir.get_next()
	var checked := 0
	while file != "":
		if file.ends_with(".tres"):
			var def := load("res://stats_system/defs/" + file) as StatDef
			assert_not_null(def, "%s should load as a StatDef" % file)
			if def != null:
				assert_ne(
					def.tint_color, Color.WHITE,
					"%s (id=%s) has no authored tint_color" % [file, def.id]
				)
				checked += 1
		file = dir.get_next()
	dir.list_dir_end()
	assert_gt(checked, 0, "expected to actually check some StatDef files")
