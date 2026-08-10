extends GutTest

## SpellBook ref-counted grant/revoke semantics (#198, #206). SpellBook itself
## is a plain Resource; sources are typed SkillNode (permanent_spells takes
## one), so fixture nodes are real (untethered) SkillNode instances rather
## than bare Objects — SpellBook never calls into them, identity is all that
## matters, same shape as test_effect.gd's `_make_node()`.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _spork: SpellDef
var _node_a: SkillNode
var _node_b: SkillNode


func before_each() -> void:
	_spork = SpellDef.new()
	_spork.name = "Spork"
	_node_a = _NODE_SCENE.instantiate()
	autofree(_node_a)
	_node_b = _NODE_SCENE.instantiate()
	autofree(_node_b)


## Example A from #206: a spell with no innate presence, granted/revoked by
## nodes, ref-counted.
func test_example_a_node_granted_spell_is_ref_counted() -> void:
	var book := SpellBook.new()
	assert_false(_spork in book.spells, "no grant yet -> not known")

	book.add_spell(_spork, _node_a)
	assert_true(_spork in book.spells, "first grant -> known")
	assert_eq(book.source_count(_spork), 1)

	book.add_spell(_spork, _node_b)
	assert_eq(book.source_count(_spork), 2, "second grant -> 2 sources, no change to membership")
	assert_eq(book.spells.count(_spork), 1, "still exactly one entry, not duplicated")

	book.remove_spell(_spork, _node_a)
	assert_true(_spork in book.spells, "one source left -> still known")
	assert_eq(book.source_count(_spork), 1)

	book.remove_spell(_spork, _node_b)
	assert_false(_spork in book.spells, "last source gone -> revoked")


## Example B from #206: an innate (null-sourced) spell is permanent — a node
## grant/revoke on top of it must not touch its permanence, and must not
## duplicate the entry in `spells` (the add_spell bug this issue fixed).
func test_example_b_innate_spell_survives_node_grant_and_revoke() -> void:
	var book := SpellBook.new()
	book.add_spell(_spork, null)
	assert_true(_spork in book.spells, "innate -> known immediately")
	assert_eq(book.spells.count(_spork), 1)

	book.add_spell(_spork, _node_a)
	assert_eq(book.spells.count(_spork), 1, "node-granting an already-innate spell must not duplicate it")
	# null is a permanent pseudo-source (never removable, see add_spell's doc),
	# so source_count is 2 here: the innate null slot + the node.
	assert_eq(book.source_count(_spork), 2)

	book.remove_spell(_spork, _node_a)
	assert_true(_spork in book.spells, "node source gone -> innate copy still stands")
	assert_eq(book.spells.count(_spork), 1)


func test_remove_spell_with_null_source_is_a_no_op() -> void:
	var book := SpellBook.new()
	book.add_spell(_spork, null)
	book.remove_spell(_spork, null)
	assert_true(_spork in book.spells, "permanent spells are not revoked via remove_spell(null)")


func test_same_source_regranting_same_spell_is_a_no_op() -> void:
	var book := SpellBook.new()
	book.add_spell(_spork, _node_a)
	book.add_spell(_spork, _node_a)
	assert_eq(book.source_count(_spork), 1, "re-granting from the same source doesn't inflate the refcount")


func test_source_a_revoking_a_spell_it_never_granted_is_a_no_op() -> void:
	var book := SpellBook.new()
	book.add_spell(_spork, _node_a)
	book.remove_spell(_spork, _node_b)
	assert_true(_spork in book.spells, "removing from an unrelated source doesn't touch the real one")
	assert_eq(book.source_count(_spork), 1)


func test_permanent_spells_includes_innate_and_core_sourced() -> void:
	var core: SkillNode = _NODE_SCENE.instantiate()
	autofree(core)
	var book := SpellBook.new()
	book.add_spell(_spork, null)
	var territory := SpellDef.new()
	territory.name = "Territory Spell"
	book.add_spell(territory, core)

	var perm := book.permanent_spells(core)
	assert_true(_spork in perm, "innate -> permanent")
	assert_true(territory in perm, "core-sourced -> permanent")


func test_permanent_spells_excludes_territory_only_grant() -> void:
	var book := SpellBook.new()
	var territory := SpellDef.new()
	territory.name = "Territory Spell"
	book.add_spell(territory, _node_a)

	var perm := book.permanent_spells(_node_b)
	assert_false(territory in perm, "granted only by a non-core node -> not permanent")
