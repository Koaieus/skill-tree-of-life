extends GutTest

## A cure reaches the core: on a core node the walk and the dose see the
## entity's status rows as well as the node's, the dose clears the core's rows
## first (table order) then the node's, and the core part survives an
## [AttackRecord] round trip.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _POISON := preload("res://effects/status/poison.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _core: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Ally"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_core.name = "core"
	_graph.add_skill_node(_core)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _core)
	_entity.core_location = _core


func _lctx() -> LandingContext:
	var ctx := PropagationContext.new()
	ctx.graph = _graph
	return LandingContext.for_test(null, _core, ctx)


func _remedy() -> Cure:
	var e := CureEntry.new()
	e.status = _POISON
	e.rate = 1.0
	var c := Cure.new()
	c.entries.assign([e])
	return c


func _core_power() -> float:
	return _entity.get_combat().get_status_power(_POISON.id)


func _node_power() -> float:
	return _core.get_combat().get_status_power(_POISON.id)


func _poison(core: float, node: float) -> void:
	if core > 0.0:
		_entity.get_combat().adjust_status_power(_POISON, core)
	if node > 0.0:
		_core.get_combat().adjust_status_power(_POISON, node)


func test_spot_stacks_count_the_core_row_on_a_core_node() -> void:
	_poison(3.0, 2.0)
	var lctx := _lctx()
	assert_almost_eq(lctx.stacks_of(_core, _POISON.id), 2.0, 0.0001, "stacks_of stays the node slice")
	assert_almost_eq(lctx.spot_stacks_of(_core, _POISON.id), 5.0, 0.0001, "node + core")


func test_plan_clears_the_core_first_then_the_node() -> void:
	_poison(3.0, 2.0)
	var plan := _remedy().plan(_core, 4.0, _lctx())
	assert_eq(plan.get("core_cleared", {}).get(_POISON, 0.0), 3.0, "the core clears its 3 first")
	assert_eq(plan.cleared.get(_POISON, 0.0), 1.0, "the node gets the 1 left")
	assert_almost_eq(float(plan.spent), 4.0, 0.0001)
	assert_almost_eq(_remedy().need_of(_core, _lctx()), 5.0, 0.0001, "need counts both holders")


func test_landing_clears_the_core_row_and_leaves_one_on_the_node() -> void:
	_poison(3.0, 2.0)
	var hit := CureInstance.new()
	hit.add(_POISON, 3.0, true)
	hit.add(_POISON, 1.0)
	hit.target = _core
	hit.land_on(_core.get_combat(), CombatWorld.live())
	assert_almost_eq(_core_power(), 0.0, 0.0001, "the core's 3 are cleared")
	assert_almost_eq(_node_power(), 1.0, 0.0001, "1 stack left on the node")


func test_status_filter_admits_a_clean_node_whose_core_is_sick() -> void:
	_poison(3.0, 0.0)
	var f := StatusFilter.new()
	f.statuses.assign([_POISON])
	assert_true(f.allows(_core, _lctx()), "the walk visits a core node with a sick core")


func test_core_part_round_trips_through_the_record() -> void:
	_poison(3.0, 2.0)
	var hit := CureInstance.new()
	hit.add(_POISON, 3.0, true)
	hit.add(_POISON, 1.0)
	hit.target = _core
	hit.origin = _core
	var o := AttackOutcome.new()
	o.hits.assign([hit])
	var rec := AttackRecord.capture(o, _graph)
	assert_true(rec.has(AttackRecord.KEY_CURE_CORE), "the core flags ride the wire")
	var back := AttackRecord.rebuild(rec, _graph).hits[0] as CureInstance
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.on_core, PackedByteArray([1, 0]))
	back.land_on(_core.get_combat(), CombatWorld.live())
	assert_almost_eq(_core_power(), 0.0, 0.0001, "the replay clears the same core row")
	assert_almost_eq(_node_power(), 1.0, 0.0001)


func test_remedy_on_a_cracked_core_leaves_one_on_the_node() -> void:
	_poison(3.0, 2.0)
	var effect := CureEffect.new()
	effect.cure = _remedy()
	effect.terms = []
	var p := CastSpell.new()
	p.damage = 4.0
	p.current_node = _core
	p.graph = _graph
	var ctx := PropagationContext.new()
	ctx.graph = _graph
	var lctx := LandingContext.for_test(p, _core, ctx)
	effect.apply(lctx)
	assert_almost_eq(p.damage, 0.0, 0.0001, "the whole dose is spent")
	var cures := lctx.cast.outcome.hits.filter(func(hit): return hit is CureInstance)
	assert_eq(cures.size(), 1)
	if cures.size() != 1:
		return
	(cures[0] as CureInstance).land_on(_core.get_combat(), CombatWorld.live())
	assert_almost_eq(_core_power(), 0.0, 0.0001, "the core clears 3")
	assert_almost_eq(_node_power(), 1.0, 0.0001, "the node clears 1, 1 left")
