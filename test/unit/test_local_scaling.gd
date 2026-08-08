extends GutTest

## #376 — the magnitude curve: a linear-ladder mutator on SkillNode that
## re-tunes local + entity-granted modifiers per allocation_level change.
##
## Architecture: SkillNode is the modifier authority; boards hold references
## to the same canonical instances, so the mutator's live `value` writes
## propagate via Resource.changed (no re-grant). The ladder is identity
## (`_local_scale(al) == al`, floored at 1 so al 0 = baseline). Per-op law:
## ADD_BASE/ADD_BONUS/INCREASE scale value × ladder(new)/ladder(old); MULTIPLY
## adds the growth part (X = 1 + (X-1)×ladder); SET opts out. Opt-out /
## custom scaling / composition mutation go through the
## `_local_scale_override` virtual.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


## ADD_BASE modifier targeting `id` with `value`.
func _add_mod(id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(_node)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()
	_graph = null
	_alloc = null
	_entity = null
	_node = null


## Own the node through the system (fill 1, pool minted) and return the live
## entity board. `modifiers` set on the node BEFORE this are granted. The cap
## is authored to 3 first so the tests can ramp the fill to 2/3 (the pool
## clamps fill to cap).
func _own() -> StatBoard:
	_node.stake_level = 3
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_entity, _node)
	return _entity.stat_board


func _set_al(v: int) -> void:
	_node.allocation_level = v


# ── Drift (decisions 6, 7) ────────────────────────────────────────────────────

func test_add_base_round_trip_is_bit_exact() -> void:
	_node.stake_level = 3
	_node.add_local_modifier(_add_mod(&"armor", 5.0))
	_set_al(1)
	assert_eq(int(_node.get_local_value(&"armor")), 5, "al=1: +5")
	_set_al(3)
	assert_eq(int(_node.get_local_value(&"armor")), 15, "al=3: +15 (5 x 3)")
	_set_al(1)
	assert_eq(int(_node.get_local_value(&"armor")), 5, "al=1 again: exactly +5 (bit-equal)")


func test_sequence_1_2_3_2_1_returns_exactly() -> void:
	_node.stake_level = 3
	_node.add_local_modifier(_add_mod(&"armor", 5.0))
	for al in [1, 2, 3, 2, 1]:
		_set_al(al)
	assert_eq(int(_node.get_local_value(&"armor")), 5,
			"1→2→3→2→1 returns exactly +5 (no drift)")


func test_multiply_1_5_round_trip_is_exact() -> void:
	# node_healing is FLOAT-typed with base 1.0, so a MULTIPLY reads straight
	# through (base 1.0 × multiplier = multiplier).
	var m := StatModifier.new()
	m.stat_id = &"node_healing"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = 1.5
	_node.stake_level = 3
	_node.add_local_modifier(m)
	_set_al(1)
	assert_almost_eq(float(_node.get_local_value(&"node_healing")), 1.5, 0.0001)
	_set_al(3)
	assert_almost_eq(float(_node.get_local_value(&"node_healing")), 2.5, 0.0001,
			"×1.5 at al=3: 1 + 0.5x3 (growth part added)")
	_set_al(1)
	assert_almost_eq(float(_node.get_local_value(&"node_healing")), 1.5, 0.0001,
			"lowered back: ×1.5 exactly")


func test_multiply_1_1_percent_more_round_trip() -> void:
	var m := StatModifier.new()
	m.stat_id = &"node_healing"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = 1.1
	_node.stake_level = 3
	_node.add_local_modifier(m)
	_set_al(2)
	assert_almost_eq(float(_node.get_local_value(&"node_healing")), 1.2, 0.0001,
			"+10% More at al=2 reads +20% More")
	_set_al(1)
	assert_almost_eq(float(_node.get_local_value(&"node_healing")), 1.1, 0.0001,
			"backed to al=1 reads ×1.1")


# ── Composition (decision 8) ──────────────────────────────────────────────────

## A composite whose override doubles its leaf-set at al >= 2 and returns its
## own children at al 1 (the identity form).
class DoublingComposite extends CompositeStatModifier:
	var last_set: Array[StatModifier] = []

	func _local_scale_override(_old_al: int, new_al: int) -> Variant:
		if new_al >= 2:
			var set: Array[StatModifier] = []
			for c in children:
				set.append(c.duplicate())
				set.append(c.duplicate())
			last_set = set
			return set
		last_set = children.duplicate()
		return children


func test_composite_swap_produces_doubled_leaves_and_restores() -> void:
	var comp := DoublingComposite.new()
	comp.children = [_add_mod(&"strength", 2.0), _add_mod(&"armor", 3.0)]
	_node.modifiers = [comp]
	var board := _own()
	var strength: Stat = board.get_stat(&"strength")
	var armor: Stat = board.get_stat(&"armor")
	assert_eq(_node.allocation_level, 1, "force-allocated at 1/1")
	assert_true(strength.has_modifier(comp.children[0]), "identity form applied at al=1")
	assert_true(armor.has_modifier(comp.children[1]))

	_set_al(2)
	assert_eq(comp.last_set.size(), 4, "override produced 2 leaves per parent leaf")
	for leaf in comp.last_set:
		assert_true(strength.has_modifier(leaf) or armor.has_modifier(leaf),
				"every scaled leaf is applied at al=2")
	assert_false(strength.has_modifier(comp.children[0]),
			"the parent's own leaves are swapped out at al=2")
	assert_eq(int(strength.get_value()), 14, "2x +2 STR lands (10 + 4)")

	_set_al(1)
	assert_true(strength.has_modifier(comp.children[0]), "backed to al=1: parent leaves restored")
	assert_true(armor.has_modifier(comp.children[1]))
	for leaf in comp.last_set:
		assert_false(strength.has_modifier(leaf) and armor.has_modifier(leaf),
				"the doubled set is fully removed")


## An effect whose scaled contribution is `new_al` copies of a +5 armor mod.
class ScalingEffect extends Effect:
	var last_set: Array[StatModifier] = []

	func _local_scale_override(_old_al: int, new_al: int) -> Variant:
		var set: Array[StatModifier] = []
		for i in new_al:
			var m := StatModifier.new()
			m.stat_id = &"armor"
			m.operation = StatModifier.Operation.ADD_BASE
			m.value = 5.0
			set.append(m)
		last_set = set
		return set


func test_effect_composition_scales_with_fill() -> void:
	var eff := ScalingEffect.new()
	eff.modifiers = [_add_mod(&"armor", 5.0)]
	_node.effects = [eff]
	var board := _own()
	var armor: Stat = board.get_stat(&"armor")
	_set_al(1)
	assert_almost_eq(float(armor.get_value()), 5.0, 0.001, "al=1: 1 effect grant")
	_set_al(2)
	assert_almost_eq(float(armor.get_value()), 10.0, 0.001, "al=2: 2 effects")
	assert_eq(eff.last_set.size(), 2)
	_set_al(3)
	assert_almost_eq(float(armor.get_value()), 15.0, 0.001, "al=3: 3 effects")
	assert_eq(eff.last_set.size(), 3)
	_set_al(1)
	assert_almost_eq(float(armor.get_value()), 5.0, 0.001, "backed to al=1: 1 effect again")


# ── Per-op defaults (decision 7) ──────────────────────────────────────────────

func test_set_is_invariant_by_default() -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.SET
	m.value = 50.0
	_node.stake_level = 3
	_node.add_local_modifier(m)
	_set_al(1)
	assert_eq(int(_node.get_local_value(&"armor")), 50)
	_set_al(3)
	assert_eq(int(_node.get_local_value(&"armor")), 50, "SET does not scale by default")


class SetOverride extends StatModifier:
	func _local_scale_override(_old_al: int, new_al: int) -> Variant:
		return 75.0 if new_al == 3 else null


func test_set_with_bespoke_override() -> void:
	var m := SetOverride.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.SET
	m.value = 50.0
	_node.stake_level = 3
	_node.add_local_modifier(m)
	_set_al(3)
	assert_eq(int(_node.get_local_value(&"armor")), 75, "override returns the literal 75 at al=3")


# ── Opt-out (decision 5) ──────────────────────────────────────────────────────

class UnscaledMod extends StatModifier:
	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func test_unscaled_override_is_invariant() -> void:
	var m := UnscaledMod.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 5.0
	_node.stake_level = 3
	_node.add_local_modifier(m)
	for al in [1, 2, 3, 1]:
		_set_al(al)
		assert_eq(int(_node.get_local_value(&"armor")), 5, "unscaled at al=%d" % al)


func test_null_override_follows_universal_law() -> void:
	var m := _add_mod(&"armor", 5.0)
	_node.stake_level = 3
	_node.add_local_modifier(m)
	_set_al(3)
	assert_eq(int(_node.get_local_value(&"armor")), 15, "plain modifier scales via the universal law")


# ── Entity-grant path (decision 3) ────────────────────────────────────────────

func test_entity_grant_scales_with_fill() -> void:
	_node.modifiers = [_add_mod(&"strength", 1.0)]
	var board := _own()
	var strength: Stat = board.get_stat(&"strength")
	assert_eq(int(strength.get_value()), 11, "al=1: entity STR+1")
	_set_al(3)
	assert_eq(int(strength.get_value()), 13, "al=3: entity STR+3")
	_set_al(1)
	assert_eq(int(strength.get_value()), 11, "al=1 again: STR+1 exactly")


func test_multi_owner_grant_computes_independently_on_each_board() -> void:
	# #377: the single-owner-SkillNode assertion this test used to pin is
	# gone — StatModifier no longer carries board-binding state, so the same
	# instance CAN sit on two boards at once and each computes independently.
	# `_node.apply_entity_modifiers_to` no longer distinguishes "already on a
	# foreign board" from "already on this one"; both are legal add_modifier
	# calls now.
	var m := _add_mod(&"strength", 5.0)
	_node.modifiers = [m]
	var board_a: StatBoard = _BOARD.duplicate(true) as StatBoard
	board_a.add_modifier(m)
	var board_b: StatBoard = _BOARD.duplicate(true) as StatBoard
	_node.apply_entity_modifiers_to(board_b)
	assert_eq(int(board_a.strength.value), int(board_a.strength.base_value) + 5,
			"board A still reflects the grant")
	assert_eq(int(board_b.strength.value), int(board_b.strength.base_value) + 5,
			"board B reflects the same grant independently")


# ── Performance + ratchet interaction ─────────────────────────────────────────

func test_mutator_walk_is_linear_and_drift_free_at_scale() -> void:
	# 14 modifiers, 2500 fill changes: the mutator is O(mods) PER CHANGE, never
	# per read — this sweep is the whole 35k-modifier walk and must stay cheap.
	var mods: Array[StatModifier] = []
	for i in 14:
		mods.append(_add_mod(&"armor", 5.0))
	for m in mods:
		_node.add_local_modifier(m)
	_node.stake_level = 2
	var t0 := Time.get_ticks_usec()
	for i in 2500:
		_set_al(1 if i % 2 == 0 else 2)
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_lt(elapsed_ms, 3000.0, "2500 changes x 14 modifiers stay well under 3s")
	_set_al(1)
	assert_eq(int(_node.get_local_value(&"armor")), 70, "and the sweep is drift-free (14 x +5)")


func test_al_ramp_does_not_interfere_with_the_hp_ratchet() -> void:
	# D-21 ratchet interaction: the mutator writes `value`, never
	# `health.base_value`, so the node pool's ratchet ("HP only ticks up")
	# stays intact across an al ramp. The +15 local node_health mod scales the
	# CAP; the ratchet grants the delta on rise and clamps (never subtracts)
	# on fall — so `current` never drops below the incoming cap and never
	# subtracts.
	_node.modifiers = [_add_mod(&"node_health", 15.0)]
	_own()
	var hp := _node.node_board.get_stat(&"node_health") as PoolStat
	hp.set_current(0.0)
	_set_al(2)
	assert_almost_eq(float(hp.value), 40.0, 0.001, "cap scales (10 + 15x2)")
	assert_almost_eq(hp.current, 15.0, 0.001, "rise grants the delta: 0 -> 15 (ticks up)")
	_set_al(3)
	assert_almost_eq(float(hp.value), 55.0, 0.001, "cap scales (10 + 15x3)")
	assert_almost_eq(hp.current, 30.0, 0.001, "second rise grants again: 15 -> 30")
	_set_al(1)
	assert_almost_eq(float(hp.value), 25.0, 0.001, "cap round-trips (10 + 15)")
	assert_almost_eq(hp.current, 25.0, 0.001, "fall clamps to the new cap — never subtracts below it")
