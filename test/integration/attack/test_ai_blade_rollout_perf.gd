extends GutTest

## Keeper: [AiBladeRollout.gather_melee_candidates] against real physics under a
## wall-clock ceiling (`elapsed < 5000 ms`). The real clock is the subject, so
## it lives in the integration tier; the rest of the rollout coverage is
## `test/unit/test_ai_blade_rollout.gd`.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _ai_entity: Entity
var _hostile: Entity


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if faction != null:
		e.faction = faction
	return e


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_ai_entity = _make_entity("AI")
	_graph.add_child(_ai_entity)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.add_child(_hostile)

	await get_tree().process_frame


# ── _reach_bound: free-rejection math, no simulation ────────────────────────
func test_gather_melee_candidates_scores_a_real_hit() -> void:
	var pivot := _spawn("Pivot")
	var member := _spawn("Member")
	var target := _spawn("Target")
	_add_edge(pivot, member)
	pivot.global_position = Vector2.ZERO
	# Member sweeps a circle of this radius around the pivot; placing the
	# target AT that same point guarantees shape overlap at t=0 regardless
	# of physics-server sync timing, rather than depending on the swing
	# reaching a particular angle by a particular frame.
	member.global_position = Vector2(60.0, 0.0)
	target.global_position = Vector2(60.0, 0.0)

	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, member)
	_alloc.force_allocate(_hostile, target)
	_hostile.core_location = target
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var visible: Array[SkillNode] = [target]
	var started := Time.get_ticks_msec()
	var candidates := AiBladeRollout.gather_melee_candidates(_ai_entity, visible, 0)
	var elapsed := Time.get_ticks_msec() - started

	assert_lt(elapsed, 5000, "rollout must complete in bounded time (no infinite MCMC)")
	assert_gt(candidates.size(), 0, "a valid pivot + induced subgraph exists -> at least one candidate")
	for c in candidates:
		assert_eq(c.mode, BattleSystem.AttackMode.MELEE)
		# Either owned node is a legitimate pivot here (both sit adjacent to
		# the target-coincident point) — the acceptance bar is "the swing
		# actually connects", not which of the two symmetric picks won.
		assert_true(c.source_node == pivot or c.source_node == member,
				"pivot must be one of the AI's own owned nodes")
	var best: AiCombatScorer.ScoredCandidate = AiCombatScorer.pick_best(candidates)
	assert_gt(best.ev, 0.0, "the best candidate should register real damage on the coincident target")


