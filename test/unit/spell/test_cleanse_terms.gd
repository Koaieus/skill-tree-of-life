extends GutTest

## A stack's cleanse WORTH is the status's fact ([method StatusDef.cleanse_worth]);
## what a cleanse does with the stacks it cleared is the spell's list of
## [CleanseTerm]s on [member CureEffect.terms]. [PayWorthTerm] appends one TRUE
## price hit after the [CureInstance] that never draws its own crit.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CORRUPTION := preload("res://effects/status/corruption.tres")
const _CURSE := preload("res://effects/status/curse.tres")
const _POISON := preload("res://effects/status/poison.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _core: SkillNode
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Ally"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_entity.stat_board.get_stat(&"crit_chance").base_value = 1.0
	_graph.add_child(_entity)

	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_core.name = "core"
	_graph.add_skill_node(_core)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "spot"
	_graph.add_skill_node(_node)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _core)
	_entity.core_location = _core
	_alloc.force_allocate(_entity, _node)


func _slice() -> NodeCombat:
	return _node.get_combat()


func _entry(def: StatusDef) -> CureEntry:
	var e := CureEntry.new()
	e.status = def
	e.rate = 1.0
	return e


func _effect(terms: Array[CleanseTerm]) -> CureEffect:
	var c := Cure.new()
	c.entries.assign([_entry(_CORRUPTION), _entry(_CURSE)])
	var e := CureEffect.new()
	e.cure = c
	e.terms = terms
	return e


## Lands a 100-dose cleanse on [member _node]; returns the outcome's hits.
func _land(effect: CureEffect) -> Array[HitInstance]:
	var p := CastSpell.new()
	p.damage = 100.0
	p.current_node = _node
	p.source = _core
	p.graph = _graph
	var ctx := PropagationContext.new()
	ctx.graph = _graph
	var lctx := LandingContext.for_test(p, _node, ctx)
	effect.apply(lctx)
	return lctx.cast.outcome.hits


func test_corruption_worth_is_one_burst_at_the_cleared_count() -> void:
	var slice := _slice()
	var hp := slice.get_max_hp()
	assert_gt(hp, 0.0, "the fixture node has max hp")
	var c := _CORRUPTION as CorruptionStatus
	assert_almost_eq(c.cleanse_worth(slice, 3.0), c.burst_amount(slice, 1, 3), 0.0001)
	assert_almost_eq(c.cleanse_worth(slice, 3.0), HitPoints.whole(3.0 * c.damage_per_power * hp), 0.0001)


func test_curse_worth_is_stacks_times_its_knob() -> void:
	var c := _CURSE as CurseStatus
	assert_almost_eq(c.cleanse_worth(_slice(), 4.0), 4.0 * c.cleanse_worth_per_stack, 0.0001)
	assert_almost_eq(c.cleanse_worth_per_stack, 1.0, 0.0001, "authored default on curse.tres")


func test_another_status_is_worth_nothing() -> void:
	assert_eq(_POISON.cleanse_worth(_slice(), 5.0), 0.0)


func test_pay_worth_appends_one_true_hit_after_the_cure() -> void:
	_slice().adjust_status_power(_CORRUPTION, 3.0)
	_slice().adjust_status_power(_CURSE, 2.0)
	var expected := _CORRUPTION.cleanse_worth(_slice(), 3.0) + _CURSE.cleanse_worth(_slice(), 2.0)
	var hits := _land(_effect([PayWorthTerm.new()]))
	assert_eq(hits.size(), 2, "the cure, then one price hit")
	if hits.size() != 2:
		return
	assert_true(hits[0] is CureInstance, "the clears come first")
	assert_almost_eq((hits[0] as CureInstance).heal, 0.0, 0.0001, "paying heals nothing")
	var price := hits[1] as DamageInstance
	assert_not_null(price)
	if price == null:
		return
	assert_eq(price.type, DamageInstance.Type.TRUE)
	assert_eq(price.basis, HitInstance.AmountBasis.FLAT)
	assert_eq(price.target, _node)
	assert_almost_eq(price.amount, expected, 0.0001, "Σ worth × scale")


func test_the_price_never_crits_at_full_crit_chance() -> void:
	_slice().adjust_status_power(_CURSE, 5.0)
	var hits := _land(_effect([PayWorthTerm.new()]))
	assert_eq(hits.size(), 2)
	if hits.size() != 2:
		return
	var price := hits[1] as DamageInstance
	price.attacker = _entity
	# Control: the same hit as a plain DamageInstance crits on this fixture.
	var control := DamageInstance.new()
	control.type = price.type
	control.amount = price.amount
	control.attacker = _entity
	control.target = price.target
	control.read_node = price.read_node
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	CritRoll.decide(control, rng, CombatWorld.live())
	assert_true(control.is_crit, "the fixture reaches 100% crit")
	CritRoll.decide(price, rng, CombatWorld.live())
	assert_false(price.is_crit, "the price draws no crit")
	var before := _slice().get_current_hp()
	price.land_on(_slice(), CombatWorld.live())
	assert_almost_eq(before - _slice().get_current_hp(), price.amount, 0.0001, "lands its number, unmultiplied")


func test_an_empty_term_list_is_a_free_cleanse() -> void:
	_slice().adjust_status_power(_CORRUPTION, 3.0)
	var hits := _land(_effect([]))
	assert_eq(hits.size(), 1, "no price hit")
	if hits.size() != 1:
		return
	assert_true(hits[0] is CureInstance)
	assert_almost_eq((hits[0] as CureInstance).heal, 0.0, 0.0001, "nothing heals")


func test_heal_per_stack_heals_the_cleared_sum() -> void:
	_slice().adjust_status_power(_CORRUPTION, 3.0)
	_slice().adjust_status_power(_CURSE, 2.0)
	var term := HealPerStackTerm.new()
	term.per_stack = 1.5
	var hits := _land(_effect([term]))
	assert_eq(hits.size(), 1)
	if hits.size() != 1:
		return
	assert_almost_eq((hits[0] as CureInstance).heal, 5.0 * 1.5, 0.0001)
