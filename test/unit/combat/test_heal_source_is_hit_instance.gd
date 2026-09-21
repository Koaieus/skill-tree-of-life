extends GutTest

## The `source` every combat door and hp signal carries is a
## [HitInstance] (nullable) — never a StringName, never the effect object that
## asked for the heal. The two callers that used to pass something else now
## build a [HealInstance] and get `effective_amount` written back onto it:
##
##   * `Entity._apply_turn_upkeep` (`core_healing` HOST_ADD upkeep) used to
##     tag [method EntityCombat.heal] with the per-turn stat id.
##   * `HealAuraEffect._on_turn_start` used to pass `self` into
##     [method SkillNode.heal_damage].
##
## Both are driven through `TurnManager.start_turn` — the production path.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_graph.add_edge(_n0, _n1)
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

	for n in [_n0, _n1]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0
	# Entity._on_turn_started runs no upkeep on turns_taken == 1 — prime that
	# throwaway turn so every turn below is a real upkeep turn.
	_turn()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.add_skill_node(sn)
	return sn


func _turn() -> void:
	_tm.start_turn(_entity)
	_tm.adopt_turn(null, _tm.turns_taken)


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


# ── entity.gd: core_healing upkeep builds a HealInstance ────────────────────

func test_core_healing_upkeep_heals_through_a_heal_instance() -> void:
	var spy := _SpyCombat.new(_entity)
	_entity._combat = spy
	var pool := _health()
	pool.deplete(4.0)  # headroom, so the heal lands in full
	var healing := float(_entity.stat_board.get_value(&"core_healing"))
	assert_gt(healing, 0.0, "needs a non-zero core_healing (authored default)")
	var before := pool.current

	_turn()

	assert_eq(spy.heal_sources.size(), 1, "one upkeep heal through the door")
	if spy.heal_sources.is_empty():
		return
	var src: Variant = spy.heal_sources[0]
	assert_true(src is HealInstance, "the upkeep tags its heal with a HealInstance, not a StringName")
	if not (src is HealInstance):
		return
	var heal := src as HealInstance
	assert_eq(heal.kind, HitInstance.Kind.HEAL)
	assert_almost_eq(heal.effective_amount, pool.current - before, 0.001,
			"the door writes what actually landed back onto the instance")
	assert_almost_eq(heal.hp_after, pool.current, 0.001, "bar numbers stamped too")


# ── heal_aura_effect.gd: the aura heals through a HealInstance ──────────────

func test_heal_aura_heals_through_a_heal_instance_naming_the_aura() -> void:
	var aura := HealAuraEffect.new()
	aura.base = 3.0
	var reach := HopRangeFinder.new()
	reach.max_hops = 1
	aura.reach = reach
	_entity.grant_effect(aura)

	var dmg := DamageInstance.new()
	dmg.amount = 20.0
	dmg.type = DamageInstance.Type.TRUE
	_n1.take_damage(dmg.amount, dmg)
	var before := _n1.get_current_hp()

	var seen: Array = []
	var handler := func(node: SkillNode, amount: float, source: HitInstance) -> void:
		if node == _n1:
			seen.append({"amount": amount, "source": source})
	Events.skill_node_healed.connect(handler)
	_turn()
	Events.skill_node_healed.disconnect(handler)

	assert_eq(seen.size(), 1, "the aura healed N1 exactly once")
	if seen.is_empty():
		return
	var src: Variant = seen[0]["source"]
	assert_true(src is HealInstance, "the aura tags its heal with a HealInstance, not itself")
	if not (src is HealInstance):
		return
	var heal := src as HealInstance
	assert_eq(heal.source, aura, "the aura is carried as HitInstance.source, never dropped")
	assert_eq(heal.target, _n1)
	assert_almost_eq(heal.effective_amount, _n1.get_current_hp() - before, 0.001,
			"the door writes what actually landed back onto the instance")
	assert_almost_eq(heal.effective_amount, float(seen[0]["amount"]), 0.001)


class _SpyCombat extends EntityCombat:
	var heal_sources: Array = []

	func heal(amount: float, source: HitInstance, raw: bool = false) -> void:
		heal_sources.append(source)
		super(amount, source, raw)
