extends GutTest

## #279 / D-27 (revised a third time) — a CoreClass .tres is a LEAF. It never
## references another CoreClass; shared modifier batches live as file-backed
## CompositeStatModifier "packs" dropped into its `modifiers` array instead
## (stats_system/packs/attribute_baseline.tres). This replaces the reverted
## class-level composition mechanism (`inherits`, then `composes`). Acceptance
## bullets from the issue's RESCOPED comment, one test group each.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")
const _NINJA := preload("res://entity/core/ninja_core.tres")


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


# --- 1. No shipped CoreClass .tres references another CoreClass ------------

func test_no_shipped_core_class_references_another_core_class() -> void:
	for core in CoreClass.load_all():
		var mods: Array = core.modifiers  # untyped: element `is` narrows cleanly
		for m in mods:
			assert_false(m is CoreClass,
					"%s's modifiers must never hold a CoreClass reference" % core.resource_path)


# --- 2. load_all() returns exactly the five selectable classes -------------

func test_load_all_returns_exactly_the_five_selectable_classes() -> void:
	# attribute_baseline.tres lives under stats_system/packs/, outside
	# entity/core/, precisely so it never shows up here as a phantom sixth
	# class (the class-registry-pollution argument that killed `composes`).
	var classes := CoreClass.load_all()
	assert_eq(classes.size(), 5,
			"expected exactly the 5 authored classes (balanced/basic_enemy/ninja/pacifist/serpent), got %d"
			% classes.size())


# --- 3. Migrated classes still produce the same applied stats (regression) -

func test_balanced_core_still_adds_ten_to_str_dex_int() -> void:
	var ent := _make_entity(_BALANCED)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))


func test_basic_enemy_core_still_adds_ten_to_str_dex_int() -> void:
	var ent := _make_entity(_BASIC_ENEMY)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))


func test_ninja_core_still_adds_ten_to_str_dex_int() -> void:
	var ent := _make_entity(_NINJA)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))


# --- 4. Editing a shared pack changes every class referencing it -----------

func test_editing_shared_pack_changes_every_referencing_class() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [_mod(&"intelligence", 10.0)]

	var class_a := CoreClass.new()
	class_a.modifiers = [pack]
	var class_b := CoreClass.new()
	class_b.modifiers = [pack]

	# Add a new grant to the shared pack BEFORE either class applies — apply()
	# reads modifiers live, so this is exactly "change one .tres and every
	# class referencing it gets the change."
	pack.children.append(_mod(&"wisdom", 7.0))

	var ent_a := _make_entity(class_a)
	var ent_b := _make_entity(class_b)
	add_child(ent_a)
	add_child(ent_b)
	await get_tree().process_frame

	for ent in [ent_a, ent_b]:
		assert_eq(int(ent.stat_board.intelligence.value), int(ent.stat_board.intelligence.base_value + 10))
		assert_eq(int(ent.stat_board.wisdom.value), int(ent.stat_board.wisdom.base_value + 7),
				"%s must see the pack's new grant too" % ent.display_name)


# --- 5. An installed pack's children are the SAME instance across entities (#377) --

func test_installed_pack_children_are_shared_not_duplicated() -> void:
	# #377: CoreClass.apply() no longer duplicates — binding lives on each
	# entity's own board, so the exact same modifier instance can sit in both
	# entities' Stat._modifiers and compute independently and correctly on
	# each. The old contract (this test's previous name) asserted the
	# opposite; #377's whole point is that sharing is now safe.
	var src_mod := _mod(&"strength", 10.0)
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [src_mod]

	var core := CoreClass.new()
	core.modifiers = [pack]

	var ent_a := _make_entity(core)
	var ent_b := _make_entity(core)
	add_child(ent_a)
	add_child(ent_b)
	await get_tree().process_frame

	assert_true(ent_a.stat_board.strength._modifiers.has(src_mod),
			"entity A must hold the pack's actual child, not a clone")
	assert_true(ent_b.stat_board.strength._modifiers.has(src_mod),
			"entity B must hold the pack's actual child, not a clone")

	# Each entity's OWN base_value still drives its OWN computed strength —
	# sharing the modifier doesn't merge the boards.
	ent_a.stat_board.strength.base_value = 0.0
	ent_b.stat_board.strength.base_value = 5.0
	assert_ne(int(ent_a.stat_board.strength.value), int(ent_b.stat_board.strength.value),
			"boards stay independent even with a shared modifier instance")

	# A live edit on the SHARED instance is now visible on both boards — that
	# is the actual capability #377 unlocks (a modifier granted to N owners
	# recalculates at each), not a hazard to guard against.
	src_mod.value = 20.0
	assert_eq(int(ent_a.stat_board.strength.value), 20,
			"shared modifier edit reaches entity A's board")
	assert_eq(int(ent_b.stat_board.strength.value), 25,
			"shared modifier edit reaches entity B's board too")
