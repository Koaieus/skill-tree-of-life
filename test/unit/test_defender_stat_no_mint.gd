extends GutTest

## #805 §3 — pins the no-mint invariant for the whole sparse, node-local,
## addon-authored DEFENDER stat family (`deflection`, `swing_drag`,
## `blunting`, `spike_regen`): reading any of them off a node that never had
## the granting addon must never allocate a Stat on that node's board, or on
## the owner's entity board.
##
## Investigated 2026-09-09 (issue #805, owner's minting worry): the invariant
## already holds — [method NodeCombat.get_local_value] misses both boards and
## returns [code]StatRegistry.get_def(id).default_value[/code], allocating
## nothing. This file is the PIN, not a fix — it exists so a future change to
## [code]get_local_value[/code] that starts minting on a miss fails a test
## instead of shipping silently. Generalizes
## `test_stake_level_poolstat.gd`'s single-stat
## `test_get_local_value_absent_stat_returns_entity_value_no_mint` across
## every stat in this tier.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

## The node-local, addon-authored defender tier named in #805 — none of these
## are entity board fields, so a bare node's read of any of them is the sparse
## (miss-both-boards) path.
const _DEFENDER_STAT_IDS: Array[StringName] = [
	&"deflection", &"swing_drag", &"blunting", &"spike_regen",
]

var _graph: Graph
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)


func _make_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.add_skill_node(sn)
	return sn


func test_reading_the_sparse_defender_family_returns_the_def_default_and_mints_nothing() -> void:
	var sn := _make_node("BareDefender")
	sn.owned_by = _entity
	# Ownership itself is allowed to mint (node_health, gated on
	# is_allocated() per .claude/rules/stats-system.md) — that's a different
	# mechanism this test isn't about. Baseline AFTER ownership, so the only
	# thing under test is whether the defender-family READS mint anything on
	# top of it.
	var baseline := sn.node_board.get_dynamic_stat_ids().duplicate()
	for id in _DEFENDER_STAT_IDS:
		var def := StatRegistry.get_def(id)
		assert_not_null(def, "fixture: %s must be a real registered stat" % id)
		var v: Variant = sn.get_local_value(id)
		assert_eq(v, def.default_value,
				"%s on a bare node must read as the def default, no mint" % id)
	assert_eq(sn.node_board.get_dynamic_stat_ids(), baseline,
			"reading the whole defender family must not have minted a single stat")


## The realistic form of the same assertion: a full-graph
## [method MeleeAttackPlan.build_obstacle_field] pass (via
## [method MeleeAttackPlan.build_blade_state], the seam a live swing actually
## runs) over a map with zero bunkers touches `deflection` on every node in the
## graph and `blunting` on every blade vertex — and must still mint nothing.
func test_full_graph_obstacle_field_pass_with_no_bunkers_mints_nothing() -> void:
	var pivot := _make_node("Pivot")
	var tip := _make_node("Tip")
	tip.global_position = Vector2(150.0, 0.0)
	_graph.add_edge(pivot, tip)
	var plain := _make_node("PlainTerritory")
	plain.global_position = Vector2(75.0, 40.0)  # within the swing's reach, no addon

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_entity, pivot)
	alloc.force_allocate(_entity, tip)
	_entity.core_location = pivot

	await get_tree().process_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = _entity
	plan.source = pivot
	plan.blade_nodes = [tip]

	# Baseline AFTER allocation (which legitimately mints node_health on pivot
	# and tip, gated on is_allocated() — a different mechanism, not under
	# test) and before the obstacle-field read this test is actually pinning.
	var baselines: Dictionary = {}
	for sn in [pivot, tip, plain]:
		baselines[sn] = sn.node_board.get_dynamic_stat_ids().duplicate()

	var state := plan.build_blade_state()
	assert_null(state.obstacles, "no bunker anywhere on the map — no field at all (#781 acceptance 8)")

	for sn in [pivot, tip, plain]:
		assert_eq(sn.node_board.get_dynamic_stat_ids(), baselines[sn],
				"%s must not have minted a stat from the obstacle-field read" % sn.name)
