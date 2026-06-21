extends GutTest

## Keystone abstract + StatKeystone: apply installs duplicated modifiers,
## remove pulls them back off, same .tres safe across many entities.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	return ent


func _stat_keystone(stat_id: StringName, op: int, value: float) -> StatKeystone:
	var ks := StatKeystone.new()
	ks.display_name = "Test Keystone"
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	ks.modifiers = [m]
	return ks


func test_apply_installs_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	var installed := ks.apply(ent, null)
	assert_eq(installed.size(), 1)
	assert_eq(int(board.strength.value), int(base_str + 25))


func test_remove_unwinds_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	var installed := ks.apply(ent, null)
	assert_eq(int(board.strength.value), int(base_str + 25))
	ks.remove(ent, null, installed)
	assert_eq(int(board.strength.value), int(base_str))


func test_same_keystone_safe_across_entities() -> void:
	# Apply the same StatKeystone .tres to two entities; modifying one's
	# board mustn't affect the other (modifiers were duplicated).
	var a := _make_entity()
	var b := _make_entity()
	add_child(a); add_child(b)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 10.0)
	var inst_a := ks.apply(a, null)
	var inst_b := ks.apply(b, null)
	assert_ne(inst_a[0], inst_b[0], "each apply must duplicate the modifier")
	# Removing from A must not affect B.
	ks.remove(a, null, inst_a)
	# B's bonus still applied.
	var base_str_b: float = b.stat_board.strength.base_value
	assert_eq(int(b.stat_board.strength.value), int(base_str_b + 10))


func test_on_turn_started_default_noop() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 1.0)
	# Just call it — assertion is "doesn't crash".
	ks.on_turn_started(ent, null)
	assert_true(true)
