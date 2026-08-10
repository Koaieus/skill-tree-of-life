extends GutTest

## SpellGrant end-to-end through AllocationSystem (#198, #206) — the user-
## facing contract, not just SpellBook's own bookkeeping (see test_spell_book.gd).
## Fixture pattern mirrors test_effect.gd's _make_entity()/_make_node().

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _make_entity() -> Entity:
	var ent := Entity.new()
	autofree(ent)
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return ent


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


func _grant(spell: SpellDef) -> SpellGrant:
	var g := SpellGrant.new()
	g.spell_def = spell
	return g


func test_allocate_grants_spell_and_deallocate_revokes() -> void:
	var alloc := AllocationSystem.new()
	autofree(alloc)
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var spork := SpellDef.new()
	spork.name = "Spork"
	node.effects = [_grant(spork)]

	assert_false(spork in ent.get_spellbook().spells, "not allocated yet -> not known")

	alloc.force_allocate(ent, node)
	assert_true(spork in ent.get_spellbook().spells, "allocating the granting node -> spell known")

	alloc.force_deallocate(node)
	assert_false(spork in ent.get_spellbook().spells, "deallocating -> spell revoked")


func test_two_granting_nodes_drop_the_spell_only_after_both_deallocate() -> void:
	var alloc := AllocationSystem.new()
	autofree(alloc)
	var ent := _make_entity()
	var node_a := _make_node()
	var node_b := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node_a)
	add_child(node_b)
	await get_tree().process_frame

	var spork := SpellDef.new()
	spork.name = "Spork"
	node_a.effects = [_grant(spork)]
	node_b.effects = [_grant(spork)]

	alloc.force_allocate(ent, node_a)
	alloc.force_allocate(ent, node_b)
	assert_eq(ent.get_spellbook().source_count(spork), 2)

	alloc.force_deallocate(node_a)
	assert_true(spork in ent.get_spellbook().spells, "one granting node still held -> spell stays")

	alloc.force_deallocate(node_b)
	assert_false(spork in ent.get_spellbook().spells, "last granting node gone -> spell drops")


## force_deallocate is the forced-dealloc cascade path (attack-triggered loss,
## not the player's own choice) — #198's triage named it explicitly as a
## revocation path distinct from a plain deallocate call.
func test_force_deallocate_cascade_revokes_the_grant() -> void:
	var alloc := AllocationSystem.new()
	autofree(alloc)
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var spork := SpellDef.new()
	spork.name = "Spork"
	node.effects = [_grant(spork)]
	alloc.force_allocate(ent, node)
	assert_true(spork in ent.get_spellbook().spells)

	var previous := alloc.force_deallocate(node)
	assert_eq(previous, ent, "force_deallocate returns the entity that lost the node")
	assert_false(spork in ent.get_spellbook().spells, "forced-dealloc cascade revokes the grant too")
