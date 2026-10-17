extends GutTest

## CureInstance landing: the planned per-status counts come off verbatim, the
## heal lands through `heal_damage` with the instance as its source, and a
## forced crit tier changes nothing (a crit would out-clear the drain).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _TEST_DEF := preload("res://test/support/status/test_status.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _attacker: Entity
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_graph = TestWorld.create(self).graph

	_alloc = TestWorld.allocator_for(_graph)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node

	_attacker = autofree(Entity.new())
	_attacker.display_name = "Attacker"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)

	# 5 poison, 3 of the fixture status, and room under max HP for a heal.
	_node.get_combat().adjust_status_power(_POISON, 5.0)
	_node.get_combat().adjust_status_power(_TEST_DEF, 3.0)
	var wound := DamageInstance.new()
	wound.type = DamageInstance.Type.TRUE
	wound.amount = 6.0
	wound.target = _node
	OutcomeApplier.land_one(wound, CombatWorld.live())


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _cure(poison: float, fixture: float, heal: float) -> CureInstance:
	var hit := CureInstance.new()
	hit.add(_POISON, poison)
	hit.add(_TEST_DEF, fixture)
	hit.heal = heal
	hit.target = _node
	hit.attacker = _attacker
	return hit


func _power(def: StatusDef, node: NodeCombat = null) -> float:
	var n := node if node != null else _node.get_combat()
	return n.get_status_power(def.id)


func test_kind_is_cure() -> void:
	assert_eq(CureInstance.new().kind, HitInstance.Kind.CURE)


func test_land_lowers_each_status_by_exactly_its_count() -> void:
	OutcomeApplier.land_one(_cure(2.0, 1.0, 0.0), CombatWorld.live())
	assert_almost_eq(_power(_POISON), 3.0, 0.0001, "5 poison − 2 cleared")
	assert_almost_eq(_power(_TEST_DEF), 2.0, 0.0001, "3 fixture − 1 cleared")


func test_land_heals_through_heal_damage_with_the_instance_as_source() -> void:
	var before := _node.get_combat().get_current_hp()
	var hit := _cure(2.0, 1.0, 3.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_current_hp() - before, 3.0, 0.0001,
			"the planned heal lands")
	assert_almost_eq(hit.hp_after - hit.hp_before, 3.0, 0.0001,
			"heal_damage stamped the bar onto the instance — it was the source")
	assert_almost_eq(hit.effective_amount, 3.0, 0.0001,
			"the heal rides effective_amount — what AttackRecord ships")


func test_zero_heal_moves_no_hp() -> void:
	var before := _node.get_combat().get_current_hp()
	OutcomeApplier.land_one(_cure(1.0, 0.0, 0.0), CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_current_hp(), before, 0.0001)


func test_a_forced_crit_tier_changes_nothing() -> void:
	var hit := _cure(2.0, 1.0, 3.0)
	hit.crit_tier = 2
	assert_false(hit.draws_own_crit(), "a cure draws no crit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	CritRoll.decide(hit, rng, CombatWorld.live())
	var before := _node.get_combat().get_current_hp()
	OutcomeApplier.land_one(hit, CombatWorld.live(), null, rng)
	assert_almost_eq(hit.crit_multiplier, 1.0, 0.0001, "no crit multiplier settles")
	assert_almost_eq(_power(_POISON), 3.0, 0.0001, "a crit clears no extra poison")
	assert_almost_eq(_power(_TEST_DEF), 2.0, 0.0001, "a crit clears no extra fixture")
	assert_almost_eq(_node.get_combat().get_current_hp() - before, 3.0, 0.0001,
			"a crit heals no extra")


func test_land_on_a_shadow_leaves_the_live_node_untouched() -> void:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	var slice := w.combat_for(_node)
	OutcomeApplier.land_one(_cure(2.0, 1.0, 0.0), w)
	assert_almost_eq(_power(_POISON, slice), 3.0, 0.0001, "the shadow slice is cured")
	assert_almost_eq(_power(_POISON), 5.0, 0.0001, "the live node keeps its stacks")
