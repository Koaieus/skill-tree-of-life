extends GutTest

## CON — fifth attribute + linear node_health intrinsic + level scaling.
## Acceptance for #269 / D-11 / D-14. The procgen cross-rollable sections
## (#5/#6, D-12) were removed in #321 v4: the off-archetype phase is gone,
## universal `archetype_stat == &""` pools are the shared defensive content.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _board() -> StatBoard:
	return _BOARD.duplicate(true) as StatBoard


# --- 1. constitution resolves + is present on a fresh default board --------

func test_constitution_resolves_via_stat_registry() -> void:
	var def := StatRegistry.get_def(&"constitution")
	assert_not_null(def, "constitution StatDef should be registered")
	assert_eq(def.id, &"constitution")


func test_constitution_present_on_default_entity_board() -> void:
	var board := _board()
	assert_not_null(board.constitution, "duplicated default board should carry a constitution stat")
	assert_eq(String(board.constitution.definition.id), "constitution")


# --- 2. CON 0 vs CON 30 -> node_health differs by exactly the intrinsic rate,
#        through the real board pipeline (apply_intrinsics(), not isolated math) --

func test_con_0_vs_30_node_health_differs_by_intrinsic_rate() -> void:
	var board_lo := _board()
	board_lo.apply_intrinsics()
	board_lo.constitution.base_value = 0.0

	var board_hi := _board()
	board_hi.apply_intrinsics()
	board_hi.constitution.base_value = 30.0

	# node_health += CON, i.e. the `value` coefficient on mod_con_to_node_health
	# times a LinearFormula passthrough of constitution. The rate lives in that
	# coefficient, NOT in a formula string, so #268 can tune it in one place.
	# TBD (#268): placeholder coefficient, 1.0.
	var expected_rate := 30.0  # 1.0 * (30 - 0)
	var diff: float = float(board_hi.node_health.get_value()) - float(board_lo.node_health.get_value())
	assert_almost_eq(diff, expected_rate, 0.001, "node_health delta should equal the CON intrinsic rate exactly")


# --- 3. Guard on D-11 decision 3: armor and min_damage_taken must NOT move
#        with CON, across that same CON 0 -> 30 comparison --------------------

func test_con_0_vs_30_does_not_change_armor_or_min_damage_taken() -> void:
	var board_lo := _board()
	board_lo.apply_intrinsics()
	board_lo.constitution.base_value = 0.0

	var board_hi := _board()
	board_hi.apply_intrinsics()
	board_hi.constitution.base_value = 30.0

	assert_almost_eq(
			float(board_lo.armor.get_value()), float(board_hi.armor.get_value()), 0.001,
			"armor must stay battlefield-found — CON must not drive it (D-11)")
	assert_almost_eq(
			float(board_lo.min_damage_taken.get_value()), float(board_hi.min_damage_taken.get_value()), 0.001,
			"min_damage_taken must stay battlefield-found — CON must not drive it (D-11)")


# --- 4. Level grants CON (D-14): a level-20 entity's node_health is
#        materially above a level-1 entity's, via the level -> CON channel --

func test_level_20_node_health_materially_above_level_1() -> void:
	var board_l1 := _board()
	board_l1.apply_intrinsics()
	board_l1.level.base_value = 1.0

	var board_l20 := _board()
	board_l20.apply_intrinsics()
	board_l20.level.base_value = 20.0

	var hp_l1 := float(board_l1.node_health.get_value())
	var hp_l20 := float(board_l20.node_health.get_value())
	assert_true(hp_l20 > hp_l1 + 10.0,
			"level 20 node_health (%s) should be materially above level 1 (%s)" % [hp_l20, hp_l1])
	# TBD (#268): target shape is ~30 HP at level 20 (vs. flat 10 today).
	assert_true(hp_l20 >= 25.0 and hp_l20 <= 35.0,
			"level 20 node_health (%s) should land near the ~30 HP target shape" % hp_l20)