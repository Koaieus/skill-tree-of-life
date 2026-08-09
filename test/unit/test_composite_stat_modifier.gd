extends GutTest

## #183 — CompositeStatModifier: a bundle that is ONE atom for storage /
## authoring / loot, but flattens into its children wherever a modifier is
## actually applied to a board or listed leaf-by-leaf.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NINJA := preload("res://entity/core/ninja_core.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _leaf(id: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


func _board() -> EntityStatBoard:
	return _BOARD.duplicate(true) as EntityStatBoard


# --- flatten() seam ---------------------------------------------------------

func test_leaf_flattens_to_itself() -> void:
	var m := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0)
	var flat := m.flatten()
	assert_eq(flat.size(), 1)
	assert_same(flat[0], m, "a leaf is its own singleton")


func test_composite_flattens_to_children_in_order() -> void:
	var a := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0)
	var b := _leaf(&"dexterity", StatModifier.Operation.ADD_BASE, -2.0)
	var c := CompositeStatModifier.new()
	c.children = [a, b]
	var flat := c.flatten()
	assert_eq(flat.size(), 2)
	assert_same(flat[0], a, "authored order preserved")
	assert_same(flat[1], b)


func test_composite_flatten_recurses_nested_bundles() -> void:
	var a := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0)
	var b := _leaf(&"dexterity", StatModifier.Operation.ADD_BASE, 3.0)
	var inner := CompositeStatModifier.new()
	inner.children = [b]
	var outer := CompositeStatModifier.new()
	outer.children = [a, inner]
	var flat := outer.flatten()
	assert_eq(flat.size(), 2, "nested composite flattens through")
	assert_same(flat[0], a)
	assert_same(flat[1], b)


func test_flatten_skips_null_children() -> void:
	var a := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0)
	var c := CompositeStatModifier.new()
	c.children = [null, a, null]
	assert_eq(c.flatten().size(), 1, "null entries are ignored, not crash")


# --- duplicate(true) deep-copies children (load-bearing) --------------------

func test_duplicate_deep_copies_children() -> void:
	var a := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0)
	var c := CompositeStatModifier.new()
	c.children = [a]
	var dup := c.duplicate(true) as CompositeStatModifier
	assert_not_same(dup.children[0], a,
			"deep dup must give the bundle its OWN child instances (formula binding-state safety)")
	assert_eq(dup.children[0].value, 5.0, "child value copied")
	a.value = 99.0
	assert_eq(dup.children[0].value, 5.0, "mutating the original child must not touch the copy")


# --- board application flattens (StatBoard.add/remove_modifier) -------------

func test_add_modifier_applies_every_child_to_the_board() -> void:
	var board := _board()
	var str_before: float = board.strength.get_value()
	var dex_before: float = board.dexterity.get_value()
	var c := CompositeStatModifier.new()
	c.children = [
		_leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0),
		_leaf(&"dexterity", StatModifier.Operation.ADD_BASE, -2.0),
	]
	board.add_modifier(c)
	assert_eq(board.strength.get_value(), str_before + 5.0, "buff child applied")
	assert_eq(board.dexterity.get_value(), dex_before - 2.0, "debuff child applied")


func test_remove_modifier_strips_every_child() -> void:
	var board := _board()
	var str_before: float = board.strength.get_value()
	var dex_before: float = board.dexterity.get_value()
	var c := CompositeStatModifier.new()
	c.children = [
		_leaf(&"strength", StatModifier.Operation.ADD_BASE, 5.0),
		_leaf(&"dexterity", StatModifier.Operation.ADD_BASE, -2.0),
	]
	board.add_modifier(c)
	board.remove_modifier(c)
	assert_eq(board.strength.get_value(), str_before, "buff child removed")
	assert_eq(board.dexterity.get_value(), dex_before, "debuff child removed")


func test_flatten_all_expands_a_mixed_list() -> void:
	var bundle := CompositeStatModifier.new()
	bundle.children = [
		_leaf(&"strength", StatModifier.Operation.ADD_BASE, 1.0),
		_leaf(&"dexterity", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var mixed: Array[StatModifier] = [_leaf(&"armor", StatModifier.Operation.ADD_BASE, 3.0), bundle]
	var flat := StatModifier.flatten_all(mixed)
	assert_eq(flat.size(), 3, "plain + 2-leaf bundle → 3 leaves (the #183 5-vs-3 listing rule)")


# --- node-local channel flattens too (SkillNode.add_local_modifier) ---------

func test_node_local_add_flattens_a_bundle_onto_node_board() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	var c := CompositeStatModifier.new()
	c.children = [
		_leaf(&"armor", StatModifier.Operation.ADD_BASE, 5.0),
		_leaf(&"min_damage_taken", StatModifier.Operation.ADD_BASE, -1.0),
	]
	node.add_local_modifier(c)
	assert_eq(node.get_local_value(&"armor"), 5.0, "bundled armor lands node-local")
	assert_eq(node.get_local_value(&"min_damage_taken"),
			StatRegistry.get_def(&"min_damage_taken").default_value - 1.0,
			"bundled debuff lands node-local")
	node.remove_local_modifier(c)
	assert_eq(node.get_local_value(&"armor"),
			StatRegistry.get_def(&"armor").default_value, "removal strips both leaves")


func test_plain_modifier_still_applies_unchanged() -> void:
	# The leaf path through the flattened add_modifier must be behaviour-identical.
	var board := _board()
	var before: float = board.strength.get_value()
	var m := _leaf(&"strength", StatModifier.Operation.ADD_BASE, 7.0)
	board.add_modifier(m)
	assert_eq(board.strength.get_value(), before + 7.0)
	board.remove_modifier(m)
	assert_eq(board.strength.get_value(), before)


# --- display: contribution_text is a bundle summary, not a phantom ----------

func test_composite_contribution_text_joins_leaves() -> void:
	var c := CompositeStatModifier.new()
	c.children = [
		_leaf(&"deallocation_points", StatModifier.Operation.ADD_BASE, 2.0),
		_leaf(&"skill_points", StatModifier.Operation.ADD_BASE, -1.0),
	]
	assert_eq(c.contribution_text(), "+2 · -1",
			"bundle summary, never the inherited '+1' phantom from the vestigial value")


# --- Ninja integration: the repackaged +2 DP / -1 SP pair still lands -------

## The end-to-end "lootable as a unit" contract: granting a composite bundle
## applies it FLATTENED onto the board. No node-side storage since #185 — loot
## is permanent board-only, not lent-on-allocate like node archetype mods (#183).
func test_looted_composite_applied_flattened_to_board() -> void:
	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(core)
	var collector := Entity.new()
	collector.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child_autofree(collector)
	collector.core_location = core
	var dp_before: float = collector.stat_board.deallocation_points.get_value()
	var sp_before: float = collector.stat_board.skill_points.get_value()

	var bundle := CompositeStatModifier.new()
	bundle.children = [
		_leaf(&"deallocation_points", StatModifier.Operation.ADD_BASE, 2.0),
		_leaf(&"skill_points", StatModifier.Operation.ADD_BASE, -1.0),
	]
	var dust := SkillDustAddon.new()
	autofree(dust)
	var mods: Array[StatModifier] = [bundle]
	dust._grant_mods(collector, mods)

	assert_eq(collector.stat_board.deallocation_points.get_value(), dp_before + 2.0,
			"bundle applied flattened onto the board")
	assert_eq(collector.stat_board.skill_points.get_value(), sp_before - 1.0)
	assert_eq(core.modifiers.size(), 0,
			"nothing stored on the core node (#185 — loot is board-only)")


func test_ninja_budget_pack_applies_both_stats_through_the_bundle() -> void:
	var board := _BOARD.duplicate(true) as EntityStatBoard
	var dp_before: float = board.deallocation_points.get_value()
	var sp_before: float = board.skill_points.get_value()
	for m in _NINJA.modifiers:
		board.add_modifier(m.duplicate(true))
	assert_eq(board.deallocation_points.get_value(), dp_before + 2.0,
			"the bundled DP buff still reaches the board")
	assert_eq(board.skill_points.get_value(), sp_before - 1.0,
			"the bundled SP tax still reaches the board — you can't cherry-pick the buff")


func test_ninja_budget_pack_is_a_single_lootable_unit() -> void:
	# The class exposes the pair as ONE modifiers entry with loots_as_unit
	# true, so the pick-N-from-M loot draw counts it once (all-or-nothing),
	# not two independent picks. ninja_core also references the shared
	# attribute_baseline.tres pack (D-27, #279), a SEPARATE composite entry
	# with loots_as_unit false — this test is about the budget pack only.
	var all_or_nothing := 0
	var mods: Array = _NINJA.modifiers  # untyped: element `is` narrows cleanly
	for m in mods:
		if m is CompositeStatModifier and (m as CompositeStatModifier).loots_as_unit:
			all_or_nothing += 1
	assert_eq(all_or_nothing, 1, "the buff/debuff pair is authored as one all-or-nothing bundle")


# --- loots_as_unit (D-27, #279) ---------------------------------------------

func test_loots_as_unit_defaults_true_preserving_pre_d27_bundle_behaviour() -> void:
	var pack := CompositeStatModifier.new()
	assert_true(pack.loots_as_unit,
			"the default must keep every pre-existing bundle all-or-nothing")


func test_ninja_budget_pack_keeps_loots_as_unit_true() -> void:
	# #183's motivating case — a buff yoked to a real tax, balanced only as a
	# unit. Nothing about D-27 changes this one.
	var pack: CompositeStatModifier = null
	var mods: Array = _NINJA.modifiers
	for m in mods:
		if m is CompositeStatModifier:
			pack = m
	assert_not_null(pack, "ninja_core must still carry its budget pack")
	assert_true(pack.loots_as_unit, "ninja's budget pack must stay all-or-nothing")
