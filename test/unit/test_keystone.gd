extends GutTest

## Keystone as a blueprint (#149): identity plus an `Array[Effect]` payload,
## with no modifier array of its own. What's left to test here is that the
## payload reaches a carrier's owner intact, and that one shared `.tres` stays
## safe across many entities.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	return ent


func _stat_keystone(stat_id: StringName, op: int, value: float) -> Keystone:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	var fx := StatEffect.new()
	fx.modifiers = [m]
	var ks := Keystone.new()
	ks.display_name = "Test Keystone"
	ks.effects = [fx]
	return ks


func test_empty_keystone_grants_nothing() -> void:
	var ks := Keystone.new()
	assert_eq(ks.effects.size(), 0, "no payload, nothing to grant")


func test_payload_reaches_the_carriers_owner() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var node: SkillNode = _NODE_SCENE.instantiate()
	autofree(node)
	var ent := _make_entity()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	node.keystone = _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var base: float = ent.stat_board.strength.value

	alloc.force_allocate(ent, node)
	assert_eq(int(ent.stat_board.strength.value), int(base + 25),
		"allocating a keystone-bearing node grants its payload")

	alloc.force_deallocate(node)
	assert_eq(int(ent.stat_board.strength.value), int(base),
		"deallocating revokes it")
	assert_eq(ent.get_effects().size(), 0)


func test_grant_installs_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	ent.grant_effect(ks.effects[0])
	assert_eq(int(board.strength.value), int(base_str + 25))


func test_revoke_unwinds_modifiers() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 25.0)
	var board := ent.stat_board
	var base_str: float = board.strength.value
	var inst := ent.grant_effect(ks.effects[0])
	assert_eq(int(board.strength.value), int(base_str + 25))
	ent.revoke_effect(inst)
	assert_eq(int(board.strength.value), int(base_str))
	assert_eq(ent.get_effects().size(), 0)


func test_same_keystone_safe_across_entities() -> void:
	# Grant the same Keystone .tres to two entities; revoking one's grant
	# mustn't affect the other (modifiers are duplicated per grant).
	var a := _make_entity()
	var b := _make_entity()
	add_child(a); add_child(b)
	await get_tree().process_frame
	var ks := _stat_keystone(&"strength", StatModifier.Operation.ADD_BASE, 10.0)
	var effect: Effect = ks.effects[0]
	var inst_a := a.grant_effect(effect)
	var inst_b := b.grant_effect(effect)
	var handles_a := inst_a.handles_for(null)
	var handles_b := inst_b.handles_for(null)
	assert_eq(handles_a.size(), 1)
	assert_ne(handles_a[0], handles_b[0], "each grant must duplicate the modifier")

	a.revoke_effect(inst_a)
	var base_str_b: float = b.stat_board.strength.base_value
	assert_eq(int(b.stat_board.strength.value), int(base_str_b + 10))
