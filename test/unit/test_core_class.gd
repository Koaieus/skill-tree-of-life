extends GutTest

## CoreClass landing tests:
##  - apply() installs the class's modifier set on the entity's stat board.
##  - The .tres is sharable: each entity gets a duplicated copy of every
##    modifier (so formula-driven entries don't crosstalk).
##  - on_turn_started() runs from Entity._on_turn_started (default no-op).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")


class _CountingCore extends CoreClass:
	var calls: int = 0
	func on_turn_started(_e: Entity) -> void:
		calls += 1


func _make_entity(core: CoreClass) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	ent.core_class = core
	return ent


func test_balanced_core_adds_ten_to_str_dex_int() -> void:
	var ent := _make_entity(_BALANCED)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	# BalancedCore is ADD_BASE +10 STR/DEX/INT. Compare the modified value
	# against base_value+10 — works regardless of the board's authored bases.
	assert_eq(int(board.strength.value), int(board.strength.base_value + 10))
	assert_eq(int(board.dexterity.value), int(board.dexterity.base_value + 10))
	assert_eq(int(board.intelligence.value), int(board.intelligence.base_value + 10))


func test_apply_duplicates_modifiers_per_entity() -> void:
	# Same shared .tres on two entities — neither board should hold a
	# reference to the source resource's modifier instances.
	var a := _make_entity(_BALANCED)
	var b := _make_entity(_BALANCED)
	add_child(a)
	add_child(b)
	await get_tree().process_frame
	var src_mod: StatModifier = _BALANCED.modifiers[0]
	for m in a.stat_board.strength._modifiers:
		assert_ne(m, src_mod, "entity A holds a clone, not the source modifier")
	for m in b.stat_board.strength._modifiers:
		assert_ne(m, src_mod, "entity B holds a clone, not the source modifier")


func test_on_turn_started_dispatches_through_entity() -> void:
	var core := _CountingCore.new()
	var ent := _make_entity(core)
	add_child(ent)
	await get_tree().process_frame
	ent._on_turn_started(ent)
	assert_eq(core.calls, 1)
