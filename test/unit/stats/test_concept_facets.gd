extends GutTest

## Concept stats are def-declared and minted at init (ADR 0054): a [StatDef]'s
## [member StatDef.role] makes it one concept's facet, [StatRegistry] indexes
## (concept, role), a non-sparse [EntityStatBoard] mints every facet at
## [method StatBoard.apply_intrinsics], and [method StatBoard.facet] is the typed read.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SPARSE := preload("res://entity/blocker/blocker_small_board.tres")


func _fresh(src: EntityStatBoard) -> EntityStatBoard:
	var board: EntityStatBoard = src.duplicate(true)
	board.apply_intrinsics()
	return board


func test_every_facet_def_has_an_identity_and_indexes_to_itself() -> void:
	var seen: Dictionary = {}
	var checked := 0
	for def in StatRegistry.get_all_defs():
		if def.role == StatDef.Role.NONE:
			continue
		assert_not_null(def.identity, "%s has a role but no identity" % def.id)
		if def.identity == null:
			continue
		var key := "%s:%d" % [def.identity.id, def.role]
		assert_false(seen.has(key), "%s and %s share %s" % [def.id, seen.get(key, &""), key])
		seen[key] = def.id
		assert_eq(StatRegistry.facet_def(def.identity.id, def.role), def, "facet_def for %s" % def.id)
		checked += 1
	assert_eq(checked, 31, "the 31 concept stats carry a role")
	assert_eq(StatRegistry.facet_defs().size(), checked, "facet_defs() is every role-bearing def")


func test_parents_carry_no_role() -> void:
	for id in [&"aspects", &"dot_stacks_per_hit", &"status_resistance"]:
		assert_eq(StatRegistry.get_def(id).role, StatDef.Role.NONE, "%s stays a typed parent" % id)


func test_default_board_mints_every_facet_at_init() -> void:
	var board := _fresh(_BOARD)
	assert_gt(StatRegistry.facet_defs().size(), 0, "expected facet defs")
	for def in StatRegistry.facet_defs():
		var s := board.get_stat(def.id)
		assert_not_null(s, "%s live after apply_intrinsics" % def.id)
		if s != null:
			assert_eq(s.base_value, def.default_value, "%s base" % def.id)
	var poison := board.facet(&"poison", StatDef.Role.ASPECT)
	assert_not_null(poison, "poison aspect facet")
	assert_same(poison, board.get_stat(&"poison_aspect"), "facet() is the board's own stat")
	assert_null(board.facet(&"scout", StatDef.Role.RESISTANCE), "scout has no resistance facet")


func test_sparse_board_stays_sparse() -> void:
	var board := _fresh(_SPARSE)
	assert_gt(StatRegistry.facet_defs().size(), 0, "expected facet defs")
	for def in StatRegistry.facet_defs():
		assert_null(board.get_stat(def.id), "%s not minted on a sparse board" % def.id)


func test_non_facet_ids_still_refused() -> void:
	for src in [_BOARD, _SPARSE]:
		var board := _fresh(src as EntityStatBoard)
		assert_null(board.ensure_facet(&"not_a_stat"), "unknown id refused")
		assert_null(board.ensure_facet(&"stake_level"), "node-only id refused")
	assert_push_warning_count(4, "each refusal warns")


func test_family_parent_folds_into_a_minted_facet() -> void:
	var board := _fresh(_BOARD)
	var curse := board.facet(&"curse", StatDef.Role.ASPECT)
	assert_not_null(curse, "curse aspect facet")
	if curse == null:
		return
	var before: float = curse.value
	var m := StatModifier.new()
	m.stat_id = &"aspects"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 1.0
	board.add_modifier(m)
	assert_eq(curse.value, before + 1.0, "+1 aspects reads +1 on the curse aspect")
