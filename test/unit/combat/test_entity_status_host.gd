extends GutTest

## #996 (hub #994): the ENTITY hosts statuses through the same [StatusHost]
## the node composes. An entity-hosted DoT ticks the `health` pool at the
## owner's turn END (ADR 0040) — so BEFORE the next `Entity.begin_turn`'s pool
## upkeep (`core_healing`), through the one pool-damage door (#995) — and the rows
## ride a core move for free because they are on the entity, not a node.
##
## Fixture: core(N0) - N1 - N2, one entity, a real [TurnManager] driving the
## turns. `poison.tres` is the authored def (halving decay, tail cut below 1);
## the numbers below are read off the boards at runtime, never pinned.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode
var _n2: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_n2 = _new_node("N2")
	_add_edge(_n0, _n1)
	_add_edge(_n1, _n2)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame

	for n in [_n0, _n1, _n2]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0
	# Entity.begin_turn runs no upkeep on turns_taken == 1 — the fixture
	# leaves the entity INSIDE that throwaway turn; every `_turn()` below ends
	# it (the status tick) and rolls into a real upkeep turn.
	_tm.start_turn(_entity)


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.add_skill_node(sn)  # through the graph, so the navigator mirrors it
	return sn


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)  # through the graph, so the navigator sees the edge


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


func _combat() -> EntityCombat:
	return _entity.get_combat()


## One turn boundary: the current turn ends through the real `end_turn` (the
## status tick), handing straight back to the lone entity's next turn start
## (its upkeep). The ready set is forced, so no initiative clock runs.
func _turn() -> void:
	for e in get_tree().get_nodes_in_group(Entity.READY_GROUP):
		e.remove_from_group(Entity.READY_GROUP)
	_entity.add_to_group(Entity.READY_GROUP)
	_tm.end_turn()


func _dpp() -> float:
	return (_POISON_DEF as PoisonStatus).damage_per_power


# ── Acceptance 4: the tick hits the pool, before the next upkeep, node HP untouched

func test_an_entity_hosted_poison_ticks_the_health_pool_before_the_next_core_healing() -> void:
	var pool := _health()
	var max_hp: float = pool.value
	pool.current = max_hp  # full: ADR 0040 ticks at turn END, so the drain
	# lands first and the next turn start's core_healing refills it (clipped
	# at the cap); the retired upkeep-then-tick order would leave max - power × dpp.
	assert_gt(float(_entity.stat_board.get_value(&"core_healing")), 0.0,
			"the ordering assert needs a non-zero core_healing (authored default)")
	var node_hp := _n0.get_current_hp()
	_combat().apply_status(_POISON_DEF, 2.0)
	assert_almost_eq(_combat().get_status_power(&"poison"), 2.0, 0.001, "the entity hosts the row")

	var healing := float(_entity.stat_board.get_value(&"core_healing"))
	_turn()
	assert_almost_eq(pool.current, minf(max_hp - 2.0 * _dpp() + healing, max_hp), 0.001,
			"turn 1's end drains power × dpp, then turn 2's upkeep heals (clipped at the cap)")
	assert_almost_eq(_n0.get_current_hp(), node_hp, 0.001, "the core NODE's HP is untouched")
	assert_almost_eq(_combat().get_status_power(&"poison"), 1.0, 0.001, "halving decay, as on a node")

	var before := pool.current
	_turn()
	assert_almost_eq(pool.current, minf(before - 1.0 * _dpp() + healing, max_hp), 0.001,
			"turn 2's end: the 1-stack tick, then turn 3's core_healing")
	assert_almost_eq(_combat().get_status_power(&"poison"), 0.0, 0.001,
			"0.5 is below the tail cut: the row is gone")
	assert_eq(_entity.get_statuses().size(), 0)


func test_an_entity_hosted_poison_drains_through_the_pool_damage_door() -> void:
	# The C0 pin (#995): every drain of `health` goes through take_pool_damage.
	var spy := _SpyCombat.new(_entity)
	_entity._combat = spy
	spy.apply_status(_POISON_DEF, 2.0)
	_turn()
	assert_eq(spy.door_calls, [2.0 * _dpp()] as Array[float], "the tick drained through the one door")


class _SpyCombat extends EntityCombat:
	var door_calls: Array[float] = []

	func take_pool_damage(amount: float, source: HitInstance) -> void:
		door_calls.append(amount)
		super(amount, source)


# ── Acceptance 5: rows ride a core move; node rows stay put ─────────────────

func test_entity_rows_survive_a_core_move_and_node_rows_stay_on_the_vacated_node() -> void:
	_combat().apply_status(_POISON_DEF, 4.0)
	_n0.get_combat().apply_status(_POISON_DEF, 8.0)
	_entity.stat_board.movement_points.current = 5.0
	assert_true(_alloc.move_core(_entity, _n1), "fixture: the core moves to the adjacent N1")
	assert_eq(_entity.core_location, _n1)
	assert_almost_eq(_combat().get_status_power(&"poison"), 4.0, 0.001, "the entity row moved with the entity")
	assert_almost_eq(_n0.get_combat().get_status_power(&"poison"), 8.0, 0.001, "the node row stayed on N0")
	assert_almost_eq(_n1.get_combat().get_status_power(&"poison"), 0.0, 0.001, "nothing migrated onto N1")

	var pool := _health()
	var before := pool.current
	var healing := float(_entity.stat_board.get_value(&"core_healing"))
	_turn()
	assert_almost_eq(pool.current, minf(before - 4.0 * _dpp() + healing, pool.value), 0.001,
			"and still ticks the pool after the move (tick at turn end, then the next upkeep)")


# ── The contract: shadow isolation + death clears ───────────────────────────

func test_a_shadow_tick_never_moves_the_live_row_or_pool() -> void:
	_combat().apply_status(_POISON_DEF, 4.0)
	var shadow := _combat().snapshot()
	_shadows.append(shadow)
	assert_almost_eq(shadow.get_status_power(&"poison"), 4.0, 0.001, "snapshot clones the entity rows")
	var live_before := _health().current
	shadow.tick_statuses()
	assert_almost_eq(_combat().get_status_power(&"poison"), 4.0, 0.001, "the live row is untouched")
	assert_almost_eq(_health().current, live_before, 0.001, "the live pool is untouched")
	assert_almost_eq(shadow.get_status_power(&"poison"), 2.0, 0.001, "the shadow row decayed")
	assert_almost_eq((shadow.board().get_stat(&"health") as PoolStat).current,
			live_before - 4.0 * _dpp(), 0.001, "the shadow pool drained")


func test_a_dead_entity_hosts_nothing() -> void:
	_combat().apply_status(_POISON_DEF, 4.0)
	_entity.die()
	assert_eq(_entity.get_statuses().size(), 0, "death clears the entity rows")
	_combat().apply_status(_POISON_DEF, 4.0)
	assert_eq(_entity.get_statuses().size(), 0, "a CLEAR def never lands on a corpse")
