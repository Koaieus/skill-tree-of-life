extends GutTest

## #997 (hub #994): [method EntityCombat.heal] is the ONE door every raise of
## the entity `health` pool takes — the twin of [method NodeCombat.heal_damage].
## It multiplies by the entity board's `healing_received` unless `raw`, and a
## negative product is TRUE damage through the pool-damage door (#995). The
## `health` pool's `core_healing` upkeep enters through it, so an entity-hosted
## Wither inverts the core's own trickle exactly as it inverts node heals.
##
## Fixture: core(N0) - N1 - N2, one entity, a real [TurnManager]. Authored
## defs are never pinned; the numbers are read off the boards at runtime.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

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
	_graph.add_edge(_n0, _n1)
	_graph.add_edge(_n1, _n2)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_entity = autofree(Entity.new())
	_entity.display_name = "Healed"
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
	_graph.add_skill_node(sn)
	return sn


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


func _combat() -> EntityCombat:
	return _entity.get_combat()


## One turn boundary: the current turn ends through the real `end_turn` (the
## status tick, ADR 0040), handing straight back to the lone entity's next
## turn start (its upkeep). The ready set is forced, so no initiative clock runs.
func _turn() -> void:
	for e in get_tree().get_nodes_in_group(Entity.READY_GROUP):
		e.remove_from_group(Entity.READY_GROUP)
	_entity.add_to_group(Entity.READY_GROUP)
	_tm.end_turn()


func _wither(stacks: float) -> WitherStatus:
	var def := WitherStatus.new()
	def.id = &"wither"
	def.factor_per_stack = 0.1
	def.power_max = 0.0
	def.decay = FractionDecay.new(0.5)
	def.reapply = StatusDef.Reapply.ACCUMULATE
	_combat().apply_status(def, stacks)
	return def


# ── Acceptance 2: the door multiplies; raw is the one bypass ────────────────

func test_heal_multiplies_by_healing_received_unless_raw() -> void:
	var pool := _health()
	pool.deplete(8.0)
	_entity.stat_board.get_stat(&"healing_received").base_value = 0.6
	var before := pool.current
	_combat().heal(5.0, null)
	assert_almost_eq(pool.current, before + 3.0, 0.001, "5 × 0.6 = 3 replenished")
	before = pool.current
	_combat().heal(5.0, null, true)
	assert_almost_eq(pool.current, before + 5.0, 0.001, "raw bypasses healing_received")


func test_heal_clamps_at_the_cap_and_ignores_a_non_positive_amount() -> void:
	var pool := _health()
	pool.restore_to_full()
	_combat().heal(5.0, null)
	assert_almost_eq(pool.current, float(pool.value), 0.001, "a full pool stays at its cap")
	pool.deplete(3.0)
	var before := pool.current
	_combat().heal(0.0, null)
	_combat().heal(-2.0, null)
	assert_almost_eq(pool.current, before, 0.001, "a non-positive raw amount is a no-op, never a drain")


func test_blocked_healing_moves_nothing() -> void:
	var pool := _health()
	pool.deplete(3.0)
	_entity.stat_board.get_stat(&"healing_received").base_value = 0.0
	var before := pool.current
	_combat().heal(5.0, null)
	assert_almost_eq(pool.current, before, 0.001, "healing_received = 0 blocks the heal outright")


# ── Acceptance 3: Wither past inversion drains the pool through the door ────

func test_a_withered_core_healing_upkeep_drains_the_pool_as_true_damage() -> void:
	var spy := _SpyCombat.new(_entity)
	_entity._combat = spy
	var pool := _health()
	pool.deplete(4.0)  # headroom, so a positive heal would have shown
	var healing := float(_entity.stat_board.get_value(&"core_healing"))
	assert_gt(healing, 0.0, "needs a non-zero core_healing (authored default)")
	var def := WitherStatus.new()
	def.id = &"wither"
	def.factor_per_stack = 0.1
	def.power_max = 0.0
	def.decay = FractionDecay.new(0.5)
	def.reapply = StatusDef.Reapply.ACCUMULATE
	# 30 stacks: ADR 0040 ticks at the turn END, so the boundary below halves
	# them to 15 BEFORE the next upkeep reads healing_received.
	spy.apply_status(def, 30.0)
	var node_hp := _n0.get_current_hp()
	var before := pool.current

	_turn()
	assert_almost_eq(float(spy.get_local_value(&"healing_received")), -0.5, 0.001,
			"15 stacks at 0.1 by the upkeep: 1 − 1.5 = −0.5 on the ENTITY board")
	assert_almost_eq(pool.current, before - ceilf(healing * 0.5), 0.001,
			"the trickle inverted: core_healing × −0.5 drains the pool, rounded up on landing")
	assert_eq(spy.door_calls.size(), 1, "exactly one drain, through take_pool_damage")
	if spy.door_calls.size() == 1:
		assert_almost_eq(float(spy.door_calls[0].amount), healing * 0.5, 0.001)
		var src: Variant = spy.door_calls[0].source
		assert_true(src is DamageInstance and (src as DamageInstance).type == DamageInstance.Type.TRUE,
				"the drain is TRUE damage")
		assert_true(src is DamageInstance and (src as DamageInstance).from_withered_heal,
				"flagged from_withered_heal — never closes a regen gate")
	assert_almost_eq(_n0.get_current_hp(), node_hp, 0.001, "the core NODE is untouched")
	# The pool has no gate: the next upkeep (stacks now 7.5 → healing_received
	# 0.25) heals again, positively.
	before = pool.current
	_turn()
	assert_almost_eq(pool.current, before + ceilf(healing * 0.25), 0.001,
			"no gate, no ramp: the decayed Wither leaves a positive product and it lands, rounded up")


class _SpyCombat extends EntityCombat:
	var door_calls: Array[Dictionary] = []

	func take_pool_damage(amount: float, source: HitInstance) -> void:
		door_calls.append({"amount": amount, "source": source})
		super(amount, source)


# ── Acceptance 6: entity resistance filters a fallen-through row ────────────

func test_entity_curse_resistance_filters_a_fallen_through_curse() -> void:
	var def := CurseStatus.new()
	def.id = &"curse"
	def.power_max = 0.0
	def.resistance_stat_id = &"curse_resistance"
	def.decay = FractionDecay.new(0.5)
	def.reapply = StatusDef.Reapply.ACCUMULATE
	_entity.stat_board.get_stat(&"curse_resistance").base_value = 0.25
	# Crack the core: TRUE damage exactly to its node HP, no overflow.
	var crack := DamageInstance.new()
	crack.type = DamageInstance.Type.TRUE
	crack.amount = _n0.get_combat().get_max_hp()
	_n0.get_combat().take_damage(crack.amount, crack)
	assert_almost_eq(_n0.get_current_hp(), 0.0, 0.001, "cracked shell")

	var hit := StatusInstance.new()
	hit.def = def
	hit.power = 4.0
	hit.target = _n0
	hit.land_on(_n0.get_combat(), CombatWorld.live())
	assert_eq(hit.host_kind, StatusInstance.HostKind.ENTITY, "fell through to the entity")
	assert_almost_eq(_combat().get_status_power(&"curse"), 4.0, 0.001,
			"the row lands raw on the entity")
	assert_almost_eq(_combat().effective_status_power(def, 4.0), 3.0, 0.001,
			"filtered by the ENTITY's curse_resistance: 4 − ⌈1 − ½⌉")
	assert_almost_eq(_n0.get_combat().get_status_power(&"curse"), 0.0, 0.001, "nothing on the node")
