extends GutTest

## entity.tscn's `spellbook` default (entity/spellbook_default.tres) is one
## resource object loaded once and cached by ResourceLoader — every
## instantiate() must get its OWN SpellBook, or granting a spell on one
## entity would leak into every other entity's book. Entity._ready()
## duplicates it (mirroring the existing stat_board pattern); this guards
## that duplication.

const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func test_two_entities_from_entity_tscn_do_not_share_a_spellbook() -> void:
	var a: Entity = _ENTITY_SCENE.instantiate()
	autofree(a)
	var b: Entity = _ENTITY_SCENE.instantiate()
	autofree(b)
	add_child(a)
	add_child(b)
	await get_tree().process_frame

	assert_ne(a.spellbook, b.spellbook, "each instance must own its own SpellBook object")

	var spork := SpellDef.new()
	spork.name = "Spork"
	var node: SkillNode = _NODE_SCENE.instantiate()
	autofree(node)
	a.get_spellbook().add_spell(spork, node)

	assert_true(spork in a.get_spellbook().spells, "granted on a")
	assert_false(spork in b.get_spellbook().spells, "must not leak into b's book")
