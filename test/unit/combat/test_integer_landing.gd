extends GutTest

## Health is INT end to end (ADR 0017): each of the four HP doors floors its
## incoming magnitude once, via [method HitPoints.land] — so the floater
## (`effective_amount`), the bar (`hp_before`/`hp_after`) and the core → entity
## overflow all read the same whole number, live and shadow alike, and a DoT
## tick or a regen ramp lands whole too.
##
## Fixture: core(N0) - N1, both owned by one entity with armor and the damage
## floor zeroed so a fractional hit reaches the door unaltered.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = _n0
	e.to = _n1
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_entity.stat_board.armor.base_value = 0.0
	_entity.stat_board.min_damage_taken.base_value = 0.0
	_graph.add_child(_entity)
	await get_tree().process_frame

	for n in [_n0, _n1]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _hit(amount: float, type: int = DamageInstance.Type.TRUE) -> DamageInstance:
	var d := DamageInstance.new()
	d.amount = amount
	d.type = type as DamageInstance.Type
	return d


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


func _assert_whole(v: float, what: String) -> void:
	assert_eq(v, floorf(v), "%s must be a whole number, got %s" % [what, v])


# ── NodeCombat.take_damage ──────────────────────────────────────────────────

func test_a_fractional_hit_lands_floored_on_a_node() -> void:
	var before := _n1.get_current_hp()
	var hit := _hit(7.9)
	_n1.take_damage(hit.amount, hit)
	assert_eq(before - _n1.get_current_hp(), 7.0, "7.9 lands as 7")
	assert_eq(hit.effective_amount, 7.0, "the floater reads the landed integer")
	_assert_whole(hit.hp_before, "hp_before")
	_assert_whole(hit.hp_after, "hp_after")


func test_a_sub_one_hit_lands_zero_and_leaves_regen_ungated() -> void:
	var before := _n1.get_current_hp()
	var hit := _hit(0.9)
	_n1.take_damage(hit.amount, hit)
	assert_eq(_n1.get_current_hp(), before, "0.9 floors to 0")
	assert_eq(hit.effective_amount, 0.0)
	assert_false(_n1._damaged_since_upkeep, "a hit that landed nothing must not gate regen")


func test_a_sub_one_underflow_still_reclassifies_as_heal_and_heals_zero() -> void:
	_n1.take_damage(5.0, null)
	var before := _n1.get_current_hp()
	# armor and the floor are INT stats, so the fraction rides the raw hit:
	# max(-5, 0.6 − 1) = −0.4.
	_entity.stat_board.armor.base_value = 1.0
	_entity.stat_board.min_damage_taken.base_value = -5.0
	var hit := _hit(0.6, DamageInstance.Type.PHYSICAL)
	_n1.take_damage(hit.amount, hit)
	assert_eq(hit.kind, HitInstance.Kind.HEAL, "the flip tests the raw -0.4, before the floor")
	assert_eq(_n1.get_current_hp(), before, "-0.4 floors to a 0 heal")
	assert_eq(hit.effective_amount, 0.0)


func test_core_overflow_into_the_entity_pool_is_whole() -> void:
	var core_hp := _n0.get_current_hp()
	var pool_before := _health().current
	var hit := _hit(core_hp + 3.7)
	_n0.take_damage(hit.amount, hit)
	var overflow := pool_before - _health().current
	assert_eq(hit.effective_amount, floorf(core_hp + 3.7))
	assert_eq(overflow, hit.effective_amount - core_hp,
		"overflow = floored effective − soaked")
	_assert_whole(overflow, "overflow")


func test_a_shadow_lands_the_same_integer_as_the_live_node() -> void:
	_entity.stat_board.armor.base_value = 1.0
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var sn: NodeCombat = shadow.shadow_for(_n1)
	var live_before := _n1.get_current_hp()
	var shadow_before := sn.get_current_hp()
	var live_hit := _hit(8.5, DamageInstance.Type.PHYSICAL)
	var shadow_hit := _hit(8.5, DamageInstance.Type.PHYSICAL)
	_n1.take_damage(live_hit.amount, live_hit)
	sn.take_damage(shadow_hit.amount, shadow_hit)
	assert_eq(live_before - _n1.get_current_hp(), 7.0, "8.5 − 1 armor = 7.5 lands as 7")
	assert_eq(shadow_before - sn.get_current_hp(), live_before - _n1.get_current_hp(),
		"shadow and live land the same integer")
	assert_eq(shadow_hit.effective_amount, live_hit.effective_amount)


# ── NodeCombat.heal_damage ──────────────────────────────────────────────────

func test_a_fractional_heal_lands_floored_on_a_node() -> void:
	_n1.take_damage(5.0, null)
	var before := _n1.get_current_hp()
	var heal := HealInstance.new()
	heal.amount = 2.9
	_n1.heal_damage(heal.amount, heal)
	assert_eq(_n1.get_current_hp() - before, 2.0, "2.9 heals 2")
	assert_eq(heal.effective_amount, 2.0)
	_assert_whole(heal.hp_after, "hp_after")


# ── EntityCombat.take_pool_damage / heal ────────────────────────────────────

func test_a_fractional_pool_drain_lands_floored() -> void:
	var before := _health().current
	_entity.get_combat().take_pool_damage(7.9, null)
	assert_eq(before - _health().current, 7.0)


func test_a_fractional_pool_heal_lands_floored() -> void:
	_entity.get_combat().take_pool_damage(6.0, null)
	var before := _health().current
	var heal := HealInstance.new()
	heal.amount = 2.9
	_entity.get_combat().heal(heal.amount, heal)
	assert_eq(_health().current - before, 2.0)
	assert_eq(heal.effective_amount, 2.0)


# ── DoT ticks land through the doors ────────────────────────────────────────

func test_a_fractional_dot_tick_lands_floored_on_a_node() -> void:
	var before := _n1.get_current_hp()
	DotTick.mint(_n1.get_combat(), 2.5 / _n1.get_max_hp(), HitInstance.AmountBasis.PERCENT_MAX)
	assert_eq(before - _n1.get_current_hp(), 2.0, "a 2.5 HP tick lands 2")


func test_a_fractional_dot_tick_lands_floored_on_the_entity_pool() -> void:
	var ec := _entity.get_combat()
	var before := _health().current
	DotTick.mint(ec, 2.5 / ec.get_max_hp(), HitInstance.AmountBasis.PERCENT_MAX)
	assert_eq(before - _health().current, 2.0, "a 2.5 HP tick lands 2")


# ── Regen ───────────────────────────────────────────────────────────────────

func test_regen_climbs_by_the_ramp_in_whole_steps() -> void:
	_n1.take_damage(_n1.get_max_hp() - 1.0, null)
	_n1.apply_turn_regen()  # consumes the damaged-this-turn gate, heals nothing
	var ramp: float = _n1.get_local_value(&"node_healing_ramp")
	var heals: Array[float] = []
	for i in 3:
		var before := _n1.get_current_hp()
		_n1.apply_turn_regen()
		heals.append(_n1.get_current_hp() - before)
	for i in heals.size():
		_assert_whole(heals[i], "regen heal %d" % i)
		if i > 0:
			assert_eq(heals[i] - heals[i - 1], ramp, "each undamaged turn heals ramp more")
	assert_gt(ramp, 0.0, "fixture: a positive ramp")
