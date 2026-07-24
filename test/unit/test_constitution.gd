extends GutTest

## CON — fifth attribute + linear node_health intrinsic + level scaling +
## softened off-archetype rolls. Acceptance for #269 / D-11 / D-12 / D-14.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _DEFENSIVE_PACK := preload("res://procgen/pools/defensive.tres")
const _WISDOM_PACK := preload("res://procgen/pools/wisdom.tres")
const _CONSTITUTION_PACK := preload("res://procgen/pools/constitution.tres")


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


# --- 5. D-12: pools stay cross-rollable. A non-CON node can still roll a
#        defensive modifier, and its off-archetype chance for a defensive
#        modifier is strictly higher than for a non-defensive off-archetype
#        modifier (DEFENSIVE role bypasses the off-phase suppression that
#        PRIMARY off-archetype content is subject to). ------------------------

func test_defensive_off_archetype_chance_exceeds_non_defensive_off_archetype() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_DEFENSIVE_PACK, _WISDOM_PACK, _CONSTITUTION_PACK]

	# A strength-primary node can still roll defensive content (node_health/armor).
	var defensive_entries := pool_set.flatten_for_phase(&"defensive", &"strength")
	assert_true(defensive_entries.size() > 0, "a non-CON node should still be able to roll defensive modifiers")

	# The comparison that matters is the SUPPRESSION MULTIPLIER applied to an
	# off-archetype roll, not raw pool weight totals (packs are authored at
	# different scales, so cross-pool weight sums aren't comparable). DEFENSIVE
	# role entries bypass off-phase suppression entirely (multiplier 1.0,
	# always fully available) — that IS the "defensive modifier" exception.
	# A non-defensive off-archetype PRIMARY pool (wisdom) is suppressed via
	# off_phase_op_weights; verify defensive's effective multiplier (1.0)
	# strictly exceeds wisdom's off-archetype multiplier for every operation
	# wisdom suppresses.
	var defensive_multiplier := 1.0  # DEFENSIVE role never consults off_phase_op_weights.
	for op in [StatModifier.Operation.ADD_BASE, StatModifier.Operation.INCREASE, StatModifier.Operation.MULTIPLY]:
		var wisdom_multiplier: float = _WISDOM_PACK.off_weight_for(op)
		assert_true(defensive_multiplier > wisdom_multiplier,
				"defensive (unsuppressed, %s) should exceed wisdom's off-archetype multiplier for op %s (%s)"
						% [defensive_multiplier, op, wisdom_multiplier])

	# D-12's explicit, named exception: CON's own off-archetype PRIMARY
	# content is suppressed less severely than a typical non-defensive
	# off-archetype pack (wisdom) — see off_phase_op_weights on
	# constitution.tres vs wisdom.tres.
	for op in [StatModifier.Operation.ADD_BASE, StatModifier.Operation.INCREASE, StatModifier.Operation.MULTIPLY]:
		var con_multiplier: float = _CONSTITUTION_PACK.off_weight_for(op)
		var wisdom_multiplier: float = _WISDOM_PACK.off_weight_for(op)
		assert_true(con_multiplier > wisdom_multiplier,
				"CON's off-archetype penalty (%s) should be less severe than wisdom's (%s) for op %s (D-12)"
						% [con_multiplier, wisdom_multiplier, op])

	# And CON's off-archetype content is still non-zero (not hard-excluded) —
	# genuinely rollable, per D-12's "neither migrate nor duplicate, stays
	# cross-rollable."
	var off_entries := pool_set.flatten_for_phase(&"off", &"strength")
	var con_off_entries := _filter_stat(off_entries, &"constitution")
	assert_true(con_off_entries.size() > 0, "CON's own off-archetype PRIMARY content should still be rollable by a non-CON node")


func _filter_stat(entries: Array[ModifierPoolEntry], stat_id: StringName) -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	for e in entries:
		if e.stat_id == stat_id:
			out.append(e)
	return out
