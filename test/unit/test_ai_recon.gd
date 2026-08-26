extends GutTest

## Coverage for #378 slice A: [AiRecon] — per-entity fog-aware hostile
## detection (independent of the shared player-only VisionSystem instance)
## and the bounded cut-vertex walk.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _BLOCKER_FACTION := preload("res://entity/factions/blocker.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _ai_entity: Entity
var _hostile: Entity
var _nodes: Array[SkillNode]


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# Line: A0 – A1 (AI territory) ... H0 (hostile, far by default).
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = _nodes[0]
	e.to = _nodes[1]
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_ai_entity = autofree(_make_entity("AI"))
	_graph.add_child(_ai_entity)

	_hostile = autofree(_make_entity("Hostile", _PLAYER_FACTION))
	_graph.add_child(_hostile)

	await get_tree().process_frame

	_alloc.force_allocate(_ai_entity, _nodes[0])
	_ai_entity.core_location = _nodes[0]
	_alloc.force_allocate(_hostile, _nodes[2])
	_hostile.core_location = _nodes[2]
	# Far apart by default; individual tests reposition to test range.
	_nodes[2].global_position = _nodes[0].global_position + Vector2(100000.0, 0.0)


# ---------------------------------------------------------------------------
# visible_enemy_nodes / has_visible_hostile
# ---------------------------------------------------------------------------

func test_hostile_within_vision_range_is_visible() -> void:
	_nodes[2].global_position = _nodes[0].global_position + Vector2(100.0, 0.0)

	assert_true(AiRecon.has_visible_hostile(_ai_entity))
	assert_true(_nodes[2] in AiRecon.visible_enemy_nodes(_ai_entity))


func test_hostile_beyond_vision_range_is_not_visible() -> void:
	_nodes[2].global_position = _nodes[0].global_position + Vector2(10000.0, 0.0)

	assert_false(AiRecon.has_visible_hostile(_ai_entity))
	assert_eq(AiRecon.visible_enemy_nodes(_ai_entity).size(), 0)


func test_allied_owned_node_never_counts_as_hostile() -> void:
	# Same default faction as the AI (npc.tres) -> ALLIED, not HOSTILE.
	var ally: Entity = autofree(_make_entity("Ally"))
	_graph.add_child(ally)
	await get_tree().process_frame
	_alloc.force_allocate(ally, _nodes[1])
	_nodes[1].global_position = _nodes[0].global_position

	assert_false(AiRecon.has_visible_hostile(_ai_entity))


func test_blocker_faction_node_in_range_is_not_an_ai_target() -> void:
	# Dormant cores are scenery: HOSTILE (so the player can clear them) but
	# `targeted_by_ai = false`, so no NPC spends AP on one.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[1])
	_nodes[1].global_position = _nodes[0].global_position + Vector2(100.0, 0.0)

	assert_false(AiRecon.has_visible_hostile(_ai_entity))
	assert_false(_nodes[1] in AiRecon.visible_enemy_nodes(_ai_entity))


func test_blocker_becomes_a_target_once_the_attacker_is_growth_capped() -> void:
	# #604: indifference is a per-turn stance, not a rule. Set by AIController
	# from `is_growth_capped`; here it is set directly to isolate the filter.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[1])
	_nodes[1].global_position = _nodes[0].global_position + Vector2(100.0, 0.0)
	_ai_entity.ai_targets_dormant_cores = true

	assert_true(AiRecon.is_ai_target(_ai_entity, _nodes[1]))
	assert_true(_nodes[1] in AiRecon.visible_enemy_nodes(_ai_entity))


func test_the_unlock_is_per_attacker() -> void:
	# The stance rides on the attacker, so an unblocked bystander is unaffected
	# by its neighbour's desperation.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[1])
	_ai_entity.ai_targets_dormant_cores = true

	assert_false(AiRecon.is_ai_target(_hostile, _nodes[1]))


func test_blocker_stays_hostile_to_the_attitude_relation() -> void:
	# Guard: the AI filter must NOT migrate into `attitude_to` — the relation
	# is what lets a player (and the damage/XP paths) attack a blocker at all.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame

	assert_eq(_hostile.attitude_to(blocker), Entity.Attitude.HOSTILE)
	assert_eq(_ai_entity.attitude_to(blocker), Entity.Attitude.HOSTILE)


func test_real_hostile_still_visible_alongside_a_blocker() -> void:
	# The filter drops only the blocker — it must not short-circuit the walk.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[1])
	_nodes[1].global_position = _nodes[0].global_position + Vector2(100.0, 0.0)
	_nodes[2].global_position = _nodes[0].global_position + Vector2(120.0, 0.0)

	var seen := AiRecon.visible_enemy_nodes(_ai_entity)

	assert_true(_nodes[2] in seen, "the player-faction node is still a target")
	assert_false(_nodes[1] in seen, "the blocker is not")


func test_no_owned_nodes_sees_nothing() -> void:
	var bystander: Entity = autofree(_make_entity("Bystander"))
	_graph.add_child(bystander)
	await get_tree().process_frame

	assert_false(AiRecon.has_visible_hostile(bystander))


# ---------------------------------------------------------------------------
# frontier_nodes / is_growth_capped
# ---------------------------------------------------------------------------

func test_frontier_is_the_unowned_neighbours() -> void:
	# Fixture: AI owns N0, edge N0-N1, N1 unowned.
	assert_eq(AiRecon.frontier_nodes(_ai_entity), [_nodes[1]] as Array[SkillNode])
	assert_false(AiRecon.is_growth_capped(_ai_entity))


func test_growth_capped_when_every_neighbour_is_held() -> void:
	# A node a Dormant Core holds is OWNED, so it is never frontier — which is
	# exactly how a ring of cores caps an entity.
	var blocker: Entity = autofree(_make_entity("Blocker", _BLOCKER_FACTION))
	_graph.add_child(blocker)
	await get_tree().process_frame
	_alloc.force_allocate(blocker, _nodes[1])

	assert_eq(AiRecon.frontier_nodes(_ai_entity).size(), 0)
	assert_true(AiRecon.is_growth_capped(_ai_entity))


func test_growth_capped_is_topological_not_a_budget_question() -> void:
	# No SP at all, but a free neighbour: not capped. An entity that banks SP
	# with nowhere to spend it is the case the unlock exists for, and "can I
	# afford one" would answer that backwards.
	_ai_entity.stat_board.skill_points.set_current(0)

	assert_false(AiRecon.is_growth_capped(_ai_entity))


# ---------------------------------------------------------------------------
# recon_bound
# ---------------------------------------------------------------------------

func test_recon_bound_is_reach_plus_allocation_cost() -> void:
	assert_almost_eq(AiRecon.recon_bound(250.0), 251.0, 0.001)
	assert_almost_eq(AiRecon.recon_bound(250.0, 2.0), 252.0, 0.001)


# ---------------------------------------------------------------------------
# cut_vertices_within
# ---------------------------------------------------------------------------

func test_cut_vertex_within_bound_is_reported() -> void:
	# Core(N0) – N1: N1 is a cut vertex only once something hangs off it.
	var n3 := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n3.name = "N3"
	_graph.skill_nodes_container.add_child(n3)
	var edge := _EDGE_SCENE.instantiate() as Edge
	edge.from = _nodes[1]
	edge.to = n3
	_graph.edges_container.add_child(edge)
	_alloc.force_allocate(_ai_entity, _nodes[1])
	_alloc.force_allocate(_ai_entity, n3)
	_nodes[1].global_position = _nodes[0].global_position + Vector2(50.0, 0.0)
	n3.global_position = _nodes[0].global_position + Vector2(100.0, 0.0)

	var cut_vertices := AiRecon.cut_vertices_within(_ai_entity, 1000.0)

	assert_true(_nodes[1] in cut_vertices, "N1 islands N3 if depleted")
	assert_false(n3 in cut_vertices, "N3 is a leaf, islands nobody")


func test_cut_vertex_outside_bound_is_excluded() -> void:
	var n3 := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n3.name = "N3"
	_graph.skill_nodes_container.add_child(n3)
	var edge := _EDGE_SCENE.instantiate() as Edge
	edge.from = _nodes[1]
	edge.to = n3
	_graph.edges_container.add_child(edge)
	_alloc.force_allocate(_ai_entity, _nodes[1])
	_alloc.force_allocate(_ai_entity, n3)
	_nodes[1].global_position = _nodes[0].global_position + Vector2(5000.0, 0.0)
	n3.global_position = _nodes[0].global_position + Vector2(5050.0, 0.0)

	var cut_vertices := AiRecon.cut_vertices_within(_ai_entity, 100.0)

	assert_false(_nodes[1] in cut_vertices, "beyond the bound, not reported")
