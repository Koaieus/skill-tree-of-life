@tool
extends GutTest

## CoreClass landing tests:
##  - apply() installs the class's modifier set on the entity's stat board.
##  - The .tres is sharable: every entity applies the SAME modifier instances
##    (#377 — no more per-entity duplication); binding lives on each entity's
##    own board, so formula-driven entries still don't crosstalk.
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
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	ent.core_class = core
	return ent


## Shape of Balanced's identity, not its magnitudes (#990 — the pinned +10 the
## issue flagged): every leaf modifier's stat_id resolves on the board and adds
## (never subtracts or sets), plus the one aura effect. A retune of the +10s
## or the per-level rate never reds this; dropping an attribute or flipping a
## sign does. Precedent: test_dexterity_pool.gd's test_dexterity_pool_shape.
func test_balanced_core_shape_is_five_positive_add_base_attributes_plus_one_aura() -> void:
	var ent := _make_entity(_BALANCED)
	add_child(ent)
	await get_tree().process_frame
	var board := ent.stat_board
	var leaves: Array[StatModifier] = []
	for m in _BALANCED.modifiers:
		if m is CompositeStatModifier:
			leaves.append_array((m as CompositeStatModifier).flatten())
		else:
			leaves.append(m)
	var seen_stats: Array[StringName] = []
	for leaf in leaves:
		assert_not_null(board.get_stat(leaf.stat_id), "%s exists on the board" % leaf.stat_id)
		assert_eq(leaf.operation, StatModifier.Operation.ADD_BASE,
				"%s is a flat attribute grant, not a percent/multiply/set" % leaf.stat_id)
		if leaf.formula == null:
			assert_gt(leaf.value, 0.0, "%s adds, never subtracts" % leaf.stat_id)
		seen_stats.append(leaf.stat_id)
	for expected in [&"strength", &"dexterity", &"intelligence", &"constitution", &"wisdom"]:
		assert_true(seen_stats.has(expected), "Balanced grants %s" % expected)
	assert_eq(_BALANCED.effects.size(), 1, "one aura — Sanctuary")
	assert_true(_BALANCED.effects[0] is HealAuraEffect, "the aura heals, not damages")


func test_apply_shares_modifiers_across_entities() -> void:
	# #377: CoreClass.apply() no longer duplicates — same shared .tres on two
	# entities means both boards hold the SAME leaf modifier instances (not
	# clones), and each still computes correctly off its own board (see
	# test_core_class_leaf.gd's fuller version of this for the reactive
	# proof). NOTE: _BALANCED.modifiers[0] is attribute_baseline.tres, a
	# CompositeStatModifier PACK — the pack itself never applies (inert
	# container, per stats-system.md); only its flatten()'d leaves do, so the
	# leaf is what must be found, not the pack.
	var a := _make_entity(_BALANCED)
	var b := _make_entity(_BALANCED)
	add_child(a)
	add_child(b)
	await get_tree().process_frame
	var src_leaf: StatModifier = null
	for leaf in _BALANCED.modifiers[0].flatten():
		if leaf.stat_id == &"strength":
			src_leaf = leaf
			break
	assert_not_null(src_leaf, "precondition: attribute_baseline.tres grants strength")
	assert_true(a.stat_board.strength._modifiers.has(src_leaf), "entity A holds the shared leaf, not a clone")
	assert_true(b.stat_board.strength._modifiers.has(src_leaf), "entity B holds the shared leaf, not a clone")


func test_on_turn_started_dispatches_through_entity() -> void:
	var core := _CountingCore.new()
	var ent := _make_entity(core)
	add_child(ent)
	await get_tree().process_frame
	ent._on_turn_started(ent)
	assert_eq(core.calls, 0, "an entity's FIRST turn runs no upkeep at all, hook included")
	ent._on_turn_started(ent)
	assert_eq(core.calls, 1)


# ── #323: the core_modifiers register ────────────────────────────────────────

func test_apply_seeds_the_core_modifiers_register() -> void:
	# CoreClass.apply() must route through Entity.grant_core_modifier() — the
	# register's SOLE write path — so LootSystem's class/register bucket has
	# something to read. Every entry in BalancedCore.modifiers lands once.
	var ent := _make_entity(_BALANCED)
	add_child(ent)
	await get_tree().process_frame
	assert_eq(ent.core_modifiers.size(), _BALANCED.modifiers.size(),
			"the register mirrors the class template one-for-one")
	for m in _BALANCED.modifiers:
		assert_true(ent.core_modifiers.has(m),
				"each class-template modifier is present in the register")


func test_grant_core_modifier_adds_exactly_once_to_register_and_board() -> void:
	var ent := autofree(Entity.new()) as Entity
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(ent)
	await get_tree().process_frame

	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 5.0
	ent.grant_core_modifier(m)

	assert_eq(ent.core_modifiers.count(m), 1, "present in the register exactly once")
	assert_true(ent.stat_board.armor._modifiers.has(m), "mirrored onto the board")


func test_loots_as_unit_pack_survives_a_register_round_trip_as_one_atom() -> void:
	# The register is the only place a `loots_as_unit = true` composite can
	# survive a loot round-trip whole (#323's RE-CUT): granted as a pack, it
	# must still be found as ONE entry, not flattened into its leaves.
	var ent := autofree(Entity.new()) as Entity
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(ent)
	await get_tree().process_frame

	var a := StatModifier.new()
	a.stat_id = &"deallocation_points"
	a.operation = StatModifier.Operation.ADD_BASE
	a.value = 2.0
	var b := StatModifier.new()
	b.stat_id = &"skill_points"
	b.operation = StatModifier.Operation.ADD_BASE
	b.value = -1.0
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = true
	pack.children = [a, b]

	ent.grant_core_modifier(pack)

	assert_eq(ent.core_modifiers.size(), 1, "the pack is a single register entry")
	assert_same(ent.core_modifiers[0], pack, "unflattened — the whole pack, not its leaves")
