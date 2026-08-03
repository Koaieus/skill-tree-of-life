extends GutTest

## #279 / D-27 — CoreClass composes by reference via @export var inherits.
## apply() walks the base first, then the class's own modifiers/effects —
## pure append, never override-by-stat_id. Acceptance bullets from the issue
## comment (D-27), one test group each.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")


func _make_entity(core: CoreClass) -> Entity:
	var ent := Entity.new()
	autofree(ent)
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	ent.core_class = core
	return ent


func _mod(id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


# --- 1. Base's modifiers AND the child's own both apply --------------------

func test_inherited_base_and_own_modifiers_both_apply() -> void:
	var base := CoreClass.new()
	base.modifiers = [_mod(&"strength", 10.0)]
	var child := CoreClass.new()
	child.inherits = base
	child.modifiers = [_mod(&"dexterity", 5.0)]

	var ent := _make_entity(child)
	add_child(ent)
	await get_tree().process_frame

	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10),
			"the base's grant must apply")
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 5),
			"the child's own grant must also apply")


# --- 2. Same-stat_id from base and child both apply (append, not override) --

func test_same_stat_id_from_base_and_child_both_apply() -> void:
	var base := CoreClass.new()
	base.modifiers = [_mod(&"strength", 10.0)]
	var child := CoreClass.new()
	child.inherits = base
	child.modifiers = [_mod(&"strength", 3.0)]

	var ent := _make_entity(child)
	add_child(ent)
	await get_tree().process_frame

	assert_eq(int(ent.stat_board.strength.value), int(ent.stat_board.strength.base_value + 13),
			"both the base's and the child's strength grants must stack, not override")


# --- 3. Editing the base changes every class composing it ------------------

func test_editing_shared_base_changes_every_composing_class() -> void:
	var base := CoreClass.new()
	base.modifiers = [_mod(&"intelligence", 10.0)]
	var class_a := CoreClass.new()
	class_a.inherits = base
	var class_b := CoreClass.new()
	class_b.inherits = base

	# Add a new grant to the shared base BEFORE either class applies —
	# apply() reads inherits.modifiers live, so this is exactly "change one
	# .tres and every class composing it gets the change."
	base.modifiers.append(_mod(&"wisdom", 7.0))

	var ent_a := _make_entity(class_a)
	var ent_b := _make_entity(class_b)
	add_child(ent_a)
	add_child(ent_b)
	await get_tree().process_frame

	for ent in [ent_a, ent_b]:
		assert_eq(int(ent.stat_board.intelligence.value), int(ent.stat_board.intelligence.base_value + 10))
		assert_eq(int(ent.stat_board.wisdom.value), int(ent.stat_board.wisdom.base_value + 7),
				"%s must see the base's new grant too" % ent.display_name)


# --- 4. Installed modifier is still a duplicate -----------------------------

func test_installed_modifier_is_a_duplicate_not_shared() -> void:
	var base := CoreClass.new()
	base.modifiers = [_mod(&"strength", 10.0)]
	var child := CoreClass.new()
	child.inherits = base

	var ent_a := _make_entity(child)
	var ent_b := _make_entity(child)
	add_child(ent_a)
	add_child(ent_b)
	await get_tree().process_frame

	var src_mod: StatModifier = base.modifiers[0]
	for m in ent_a.stat_board.strength._modifiers:
		assert_ne(m, src_mod, "entity A must hold a clone of the base's modifier, not the source")
	for m in ent_b.stat_board.strength._modifiers:
		assert_ne(m, src_mod, "entity B must hold a clone of the base's modifier, not the source")

	# Mutating the installed clone must not perturb the shared base or the
	# sibling entity.
	ent_a.stat_board.strength._modifiers[0].value = 999.0
	assert_eq(src_mod.value, 10.0, "mutating the installed clone must not touch the shared .tres")
	assert_ne(int(ent_b.stat_board.strength.value), int(ent_a.stat_board.strength.value),
			"mutating entity A's clone must not affect entity B")


# --- 5. An inheritance cycle is detected and errors, not hangs -------------

func test_inheritance_cycle_errors_instead_of_hanging() -> void:
	var a := CoreClass.new()
	var b := CoreClass.new()
	a.inherits = b
	b.inherits = a

	var ent := _make_entity(a)
	add_child(ent)
	await get_tree().process_frame

	assert_push_error(
		"CoreClass.apply: inheritance cycle detected at '' — 'inherits' chain never terminates")


# --- 6. balanced_core / basic_enemy_core produce the same stats post-migration

func test_balanced_core_still_adds_ten_to_str_dex_int_after_migration() -> void:
	var ent := _make_entity(_BALANCED)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))


func test_basic_enemy_core_still_adds_ten_to_str_dex_int_after_migration() -> void:
	var ent := _make_entity(_BASIC_ENEMY)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))
