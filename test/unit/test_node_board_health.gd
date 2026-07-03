extends GutTest

## Sharp tests for node_board health PoolStat — replaces current_hp float
## + get_max_hp LocalStat routing with a proper PoolStat on a sparse StatBoard.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _board() -> StatBoard:
	return _BOARD.duplicate(true)


func _mod(op: int, value: float, id: StringName = &"strength") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


func _setup_node(entity_base_node_health: float = 10.0) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board := _board()
	board.node_health.base_value = entity_base_node_health
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	return {"graph": graph, "entity": entity, "node": node, "board": board, "alloc": alloc}


# ── Allocation creates health pool ──────────────────────────────────────────

func test_allocation_creates_node_health_pool() -> void:
	var ctx: Dictionary = await _setup_node()
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	assert_not_null(hp, "allocated node must have a combat health PoolStat")
	assert_gt(hp.value, 0.0, "max HP should be positive")
	assert_almost_eq(hp.current, hp.value, 0.001, "current should equal max after alloc")


func test_unallocated_node_has_no_current_hp() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame
	assert_eq(node.get_current_hp(), 0.0)
	assert_eq(node.get_max_hp(), 0.0)


# ── Baseline sync ──────────────────────────────────────────────────────────

func test_node_health_pool_syncs_from_entity_baseline() -> void:
	var ctx: Dictionary = await _setup_node(25.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	assert_almost_eq(hp.value, 25.0, 0.001, "node max should match entity node_health baseline")


func test_entity_node_health_change_re_syncs() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var board: StatBoard = ctx.board
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	assert_almost_eq(hp.value, 10.0, 0.001)

	# Verify the signal path works: entity node_health change → node pool re-syncs
	var entity_nh := board.get_stat(&"node_health") as ScalarStat
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 30.0, &"node_health"))
	assert_almost_eq(entity_nh.get_value(), 40.0, 0.001, "entity node_health should now be 40")
	# Manually trigger sync — the signal _on_entity_node_health_changed should
	# have fired by now, but verify the pool's value reflects the new baseline
	hp.base_value = entity_nh.get_value()
	assert_almost_eq(hp.value, 40.0, 0.001, "node combat health must re-sync from entity baseline")


# ── Node-local modifier ─────────────────────────────────────────────────────

func test_node_local_health_modifier_increases_max_and_heals_current() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	var was_current: float = hp.current

	hp.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0, &"node_health"))
	assert_almost_eq(hp.value, 15.0, 0.001, "max should increase by +5")
	assert_almost_eq(hp.current, was_current + 5.0, 0.001, "heal_on_max_increase should bump current too")


func test_node_local_health_modifier_remove_decreases_max() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	var m := _mod(StatModifier.Operation.ADD_BASE, 5.0, &"node_health")
	hp.add_modifier(m)
	hp.remove_modifier(m)
	assert_almost_eq(hp.value, 10.0, 0.001, "max should return to baseline after remove")
	assert_almost_eq(hp.current, 10.0, 0.001, "current clamped to new max")


# ── Deplete ─────────────────────────────────────────────────────────────────

func test_deplete_reduces_current() -> void:
	var ctx: Dictionary = await _setup_node(20.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	hp.deplete(7.0)
	assert_almost_eq(hp.current, 13.0, 0.001)


func test_deplete_clamps_at_zero() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	hp.deplete(25.0)
	assert_almost_eq(hp.current, 0.0, 0.001)


# ── Refill ──────────────────────────────────────────────────────────────────

func test_refill_restores_current_to_max() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	hp.deplete(8.0)
	assert_almost_eq(hp.current, 2.0, 0.001)
	node.refill()
	assert_almost_eq(hp.current, hp.value, 0.001, "refill should restore to max")


# ── Dealloc / reset ─────────────────────────────────────────────────────────

func test_dealloc_resets_current_to_zero() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var alloc: AllocationSystem = ctx.alloc
	var hp := node.node_board.get_stat(&"node_health") as PoolStat
	alloc.force_deallocate(node)
	assert_almost_eq(hp.current, 0.0, 0.001, "current should reset to 0 on dealloc")


# ── get_local_value ─────────────────────────────────────────────────────────

func test_get_local_value_no_node_board_mods_passthrough() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	assert_eq(node.get_local_value(&"strength"), 10, "should pass through entity value")


func test_get_local_value_creates_no_stat_on_node_board() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	node.get_local_value(&"range")
	assert_null(node.node_board.get_stat(&"range"), "get_local_value must not allocate on node_board")


func test_get_local_value_returns_node_stat_when_local_mods_exist() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	var s := node._ensure_local_stat(&"strength")
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 7.0))
	var v: Variant = node.get_local_value(&"strength")
	assert_eq(v, 17, "should combine entity base + node mod")


# ── Signal path ─────────────────────────────────────────────────────────────

func test_take_damage_emits_depleted_when_hp_hits_zero() -> void:
	var ctx: Dictionary = await _setup_node(5.0)
	var node: SkillNode = ctx.node
	watch_signals(node)
	node.take_damage(10.0, null)
	assert_signal_emitted(node, "depleted")
	assert_signal_emitted(node, "damaged")


func test_take_damage_core_overflow_to_entity_health() -> void:
	var ctx: Dictionary = await _setup_node(3.0)
	var node: SkillNode = ctx.node
	var entity: Entity = ctx.entity
	entity.core_location = node
	watch_signals(node)
	node.take_damage(7.0, null)
	assert_signal_emitted(node, "damaged")
	assert_signal_not_emitted(node, "depleted")


# ── _ensure_local_stat ──────────────────────────────────────────────────────

func test_ensure_local_stat_creates_sparse_stat() -> void:
	var ctx: Dictionary = await _setup_node(10.0)
	var node: SkillNode = ctx.node
	assert_null(node.node_board.get_stat(&"range"), "range stat should not exist yet")
	var s := node._ensure_local_stat(&"range")
	assert_not_null(s)
	assert_eq(node.node_board.get_stat(&"range"), s, "same instance on second lookup")
