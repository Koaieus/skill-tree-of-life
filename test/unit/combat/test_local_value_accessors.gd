extends GutTest

## `NodeCombat.get_local_value` understands #333's accessor tokens (#702).
##
## The bug this pins: a bare `node_health` reads the pool's CAP, and since #660
## that cap is a live provider off the OWNER's baseline — so it is very nearly
## the same number on every node one entity owns, and a ranker sorting on it is
## mostly resolving ties. `node_health__current` is the per-node signal.
##
## Fixture is deliberately the same shape as test_node_board_health.gd's.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _setup(node_count: int = 1, entity_base_node_health: float = 10.0) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board: EntityStatBoard = _BOARD.duplicate(true)
	board.node_health.base_value = entity_base_node_health
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var nodes: Array[SkillNode] = []
	for i in node_count:
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		n.name = "N%d" % i
		graph.skill_nodes_container.add_child(n)
		nodes.append(n)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for n in nodes:
		alloc.force_allocate(entity, n)

	return {"graph": graph, "entity": entity, "nodes": nodes, "alloc": alloc}


func _hp(node: SkillNode) -> PoolStat:
	return node.node_board.get_stat(&"node_health") as PoolStat


# ── The token resolves to `.current`, not the cap ───────────────────────────

func test_accessor_token_reads_pool_current_not_cap() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]
	var hp := _hp(node)
	var cap: float = hp.value
	hp.set_current(3.0)

	assert_almost_eq(
		float(node.get_local_value(&"node_health__current")), 3.0, 0.001,
		"`node_health__current` must read the damaged current, not the cap")
	assert_gt(cap, 3.0, "fixture is only meaningful if the cap and current differ")


func test_bare_id_still_reads_the_cap() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]
	var hp := _hp(node)
	var cap: float = hp.value
	hp.set_current(3.0)

	assert_almost_eq(
		float(node.get_local_value(&"node_health")), cap, 0.001,
		"a bare id is unchanged by #702 — it still reads the modifier-computed cap")


func test_current_varies_per_node_where_the_cap_does_not() -> void:
	# The whole point of the issue: two nodes of one entity share a cap, so the
	# cap cannot rank them. Damage is what distinguishes them.
	var ctx: Dictionary = await _setup(2)
	var a: SkillNode = ctx.nodes[0]
	var b: SkillNode = ctx.nodes[1]
	_hp(a).set_current(2.0)
	_hp(b).set_current(8.0)

	assert_almost_eq(
		float(a.get_local_value(&"node_health")),
		float(b.get_local_value(&"node_health")), 0.001,
		"both nodes' caps come off the same owner baseline — a tie")
	assert_lt(
		float(a.get_local_value(&"node_health__current")),
		float(b.get_local_value(&"node_health__current")),
		"currents must order the two nodes")


# ── The grammar generalises past pools, with no further code ────────────────

func test_entity_scope_accessor_resolves_through_the_owner_board() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]
	var entity: Entity = ctx.entity
	var sp := entity.stat_board.get_stat(&"skill_points") as SkillPointStat
	assert_not_null(sp, "fixture needs the entity's SkillPointStat")
	var before: float = float(node.get_local_value(&"skill_points__wounded"))
	sp.wounded = before + 2.0

	assert_almost_eq(
		float(node.get_local_value(&"skill_points__wounded")), before + 2.0, 0.001,
		"a stat absent from the node board falls through to the owner's — this is "
		+ "what makes the resolution order load-bearing, not the pool special-case")


# ── Failure modes ───────────────────────────────────────────────────────────

func test_unknown_accessor_degrades_to_the_computed_value() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]
	var cap: float = _hp(node).value
	_hp(node).set_current(3.0)

	# Stat.read_accessor's policy, deliberately NOT overridden per-caller: warn
	# once, degrade to get_value(). A 0.0 here would silently rank this node
	# worst — the exact plausible-looking wrong answer #702 was filed about.
	assert_almost_eq(
		float(node.get_local_value(&"node_health__nonsense")), cap, 0.001,
		"an unknown accessor degrades to the computed value, never to 0.0")


func test_accessor_on_a_plain_scalar_degrades_to_its_value() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]
	var bare: float = float(node.get_local_value(&"armor"))

	assert_almost_eq(
		float(node.get_local_value(&"armor__current")), bare, 0.001,
		"a ScalarStat answers no accessors — degrade to its value, don't zero it")


func test_unknown_base_id_falls_through_to_zero_not_an_error() -> void:
	var ctx: Dictionary = await _setup()
	var node: SkillNode = ctx.nodes[0]

	assert_almost_eq(
		float(node.get_local_value(&"no_such_stat__current")), 0.0, 0.001,
		"an unregistered base id has no value to degrade to")
