extends GutTest

## Keystone + StatKeystone, now expressed through the Effect substrate (#4):
## `get_effects()` wraps the modifier bundle, Entity.grant_effect installs
## duplicated modifiers, revoke_effect pulls them back off, and the same .tres
## stays safe across many entities.

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


func test_get_effects_wraps_modifier_bundle() -> void:
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var fx := ks.get_effects()
	assert_eq(fx.size(), 1, "a modifiers-only keystone yields one implicit StatEffect")
	assert_true(fx[0] is StatEffect)
	assert_eq(fx[0].modifiers.size(), 1)


func test_empty_keystone_yields_no_effects() -> void:
	var ks := StatKeystone.new()
	assert_eq(ks.get_effects().size(), 0, "no modifiers, no effects — nothing to grant")


func test_grant_installs_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	ent.grant_effect(ks.get_effects()[0])
	assert_eq(int(board.strength.value), int(base_str + 25))


func test_revoke_unwinds_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	var inst := ent.grant_effect(ks.get_effects()[0])
	assert_eq(int(board.strength.value), int(base_str + 25))
	ent.revoke_effect(inst)
	assert_eq(int(board.strength.value), int(base_str))
	assert_eq(ent.get_effects().size(), 0)


func test_same_keystone_safe_across_entities() -> void:
	# Grant the same StatKeystone .tres to two entities; revoking one's grant
	# mustn't affect the other (modifiers are duplicated per grant).
	var a := _make_entity()
	var b := _make_entity()
	add_child(a); add_child(b)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 10.0)
	var effect := ks.get_effects()[0]
	var inst_a := a.grant_effect(effect)
	var inst_b := b.grant_effect(effect)
	var handles_a := inst_a.handles_for(null)
	var handles_b := inst_b.handles_for(null)
	assert_eq(handles_a.size(), 1)
	assert_ne(handles_a[0], handles_b[0], "each grant must duplicate the modifier")

	a.revoke_effect(inst_a)
	var base_str_b: float = b.stat_board.strength.base_value
	assert_eq(int(b.stat_board.strength.value), int(base_str_b + 10))
