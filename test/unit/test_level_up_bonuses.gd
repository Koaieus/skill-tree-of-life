extends GutTest

## #194 — per-level core-class stat bonuses, as ordinary formula-bound entries
## in `CoreClass.modifiers`. No `level_up_modifiers` field, no per-level-up
## mutation: one modifier per stat, `value` as the coefficient and the shared
## `level_scaling` formula (`level - 1`) as the variable part. Level-up writes
## `level.base_value`, which emits value_changed → bound modifiers recompute.
##
## The curve is `level - 1` (not `level`) so a fresh level-1 entity sits exactly
## on its authored baseline and each level-up adds the coefficient.
##
## `level_scaling.tres` is a SHARED external resource on purpose — one file
## tunes the curve for every class. That relies on `duplicate(true)` preserving
## the identity of a file-backed sub-resource (it copies inline ones, not
## file-backed ones); `test_shared_formula_survives_per_entity_duplication`
## pins that, since inlining the formula would silently fork it per entity.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _LEVEL_SCALING := preload("res://stats_system/formulas/level_scaling.tres")

const _SCALED := [&"strength", &"dexterity", &"intelligence"]


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	ent.core_class = _BALANCED
	add_child(ent)
	await get_tree().process_frame
	return ent


func test_level_one_entity_sits_on_the_flat_baseline() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board
	# `level - 1` == 0 at level 1, so the scaling modifiers contribute nothing
	# and Balanced reads exactly its authored +10 — unchanged from pre-#194.
	for id in _SCALED:
		var s := board.get_stat(id)
		assert_eq(int(s.value), int(s.base_value + 10), "%s is baseline at level 1" % id)


func test_each_level_grants_one_point_per_scaled_stat() -> void:
	var ent: Entity = await _make_entity()
	var board := ent.stat_board
	var at_1: Dictionary = {}
	for id in _SCALED:
		at_1[id] = int(board.get_stat(id).value)

	ent.level += 1
	for id in _SCALED:
		assert_eq(int(board.get_stat(id).value), at_1[id] + 1, "%s +1 at level 2" % id)

	ent.level += 8
	for id in _SCALED:
		assert_eq(int(board.get_stat(id).value), at_1[id] + 9, "%s tracks level 10 exactly" % id)


func test_level_up_through_the_xp_pool_drives_the_bonuses() -> void:
	# The real path: fill XP → _on_xp_replenished bumps level.base_value.
	var ent: Entity = await _make_entity()
	var board := ent.stat_board
	var str_at_1: int = int(board.strength.value)
	board.xp.set_current(board.xp.value)
	await get_tree().process_frame
	assert_eq(int(board.level.value), 2, "XP fill leveled the entity")
	assert_eq(int(board.strength.value), str_at_1 + 1, "STR followed the XP-driven level-up")


func test_shared_formula_survives_per_entity_duplication() -> void:
	# CoreClass.apply() deep-duplicates each modifier. The formula must NOT be
	# forked with it — every entity reads the one shared curve, so retuning
	# level_scaling.tres retunes every class. Guards against the formula being
	# inlined back into balanced_core.tres, which would break this silently.
	var a: Entity = await _make_entity()
	var b: Entity = await _make_entity()
	for board in [a.stat_board, b.stat_board]:
		var bound := 0
		for m in board.strength._modifiers:
			if m.formula != null:
				assert_eq(m.formula, _LEVEL_SCALING, "board reads the shared curve, not a fork")
				bound += 1
		assert_eq(bound, 1, "exactly one level-scaling modifier on strength")


func test_entities_do_not_crosstalk() -> void:
	# The modifiers themselves DO get duplicated (they carry binding state).
	var a: Entity = await _make_entity()
	var b: Entity = await _make_entity()
	var b_str_at_1: int = int(b.stat_board.strength.value)
	a.level += 5
	assert_eq(int(b.stat_board.strength.value), b_str_at_1, "leveling A leaves B untouched")


func test_the_level_bonuses_are_filterable_by_formula_input() -> void:
	# The #199 hook: "which of my modifiers scale with level?" is a filter on
	# the formula's declared inputs — no marker field, no resource identity.
	# Same predicate LootSystem uses with the opposite sign, so the two can't
	# disagree about what counts as a level bonus.
	var level_scaled := _BALANCED.modifiers.filter(
		func(m: StatModifier) -> bool: return m.scales_with(&"level")
	)
	assert_eq(level_scaled.size(), 3, "STR/DEX/INT scale with level")
	var ids: Array = []
	for m in level_scaled:
		ids.append(m.stat_id)
	for id in _SCALED:
		assert_has(ids, id)
