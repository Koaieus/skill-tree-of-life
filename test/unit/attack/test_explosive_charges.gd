extends GutTest

## The explosive charge status (#1594): its def's decay, its death removal
## (every charge spent at once) and [method ExplosiveSpread.radius_for]'s
## shape. Ratios, never the authored literals — knobs move.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EXPLOSIVE_PATH := "res://effects/status/explosive.tres"

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = autofree(Entity.new())
	_entity.display_name = "Bomber"
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)
	_nodes = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]


func _def() -> StatusDef:
	return load(_EXPLOSIVE_PATH) as StatusDef


func _spread() -> ExplosiveSpread:
	return _def().spread as ExplosiveSpread


# --- acceptance 8: radius_for ratios ---------------------------------------

func test_radius_doubles_with_node_radius() -> void:
	var s := ExplosiveSpread.new()
	var r := s.radius_for(32.0, 1)
	assert_gt(r, 0.0, "one charge reaches somewhere")
	assert_almost_eq(s.radius_for(64.0, 1) / r, 2.0, 0.0001, "the bomb is the node: radius scales linearly")


func test_radius_doubles_when_charges_go_times_four() -> void:
	var s := ExplosiveSpread.new()
	assert_almost_eq(s.radius_for(32.0, 12) / s.radius_for(32.0, 3), 2.0, 0.0001, "sqrt(charges)")


func test_radius_flat_at_exponent_zero() -> void:
	var s := ExplosiveSpread.new()
	s.charge_exponent = 0.0
	assert_almost_eq(s.radius_for(32.0, 9), s.radius_for(32.0, 1), 0.0001, "exponent 0 ignores charges")


func test_radius_zero_without_charges() -> void:
	assert_eq(ExplosiveSpread.new().radius_for(32.0, 0), 0.0, "no charge, no boom")


# --- acceptance 6: decay ------------------------------------------------------

func test_two_charges_lose_per_tick_at_turn_end() -> void:
	var def := _def()
	assert_not_null(def, "explosive.tres authored")
	var per_tick: float = (def.decay as FlatDecay).per_tick
	var c := _nodes[0].get_combat()
	c.apply_status(def, 2.0)
	c.tick_statuses()
	assert_almost_eq(c.get_status_power(def.id), 2.0 - per_tick, 0.0001, "decays by per_tick at turn end")


# --- acceptance 5: death spends every charge at once -------------------------

func test_death_removal_spends_all_charges_in_one_transfer() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	var out := _spread().on_removed(field, removed, StatusSpread.CAUSE_DEATH)
	assert_eq(out.size(), 1, "one spend, not one per charge")
	assert_null(out[0].to, "charges burn, never spill onto a neighbour")
	assert_eq(out[0].amount, 3.0, "every charge is spent")


func test_dealloc_spends_nothing() -> void:
	var def := _def()
	var c := _nodes[0].get_combat()
	c.apply_status(def, 3.0)
	var field := StackField.over_world(def, def.spread.ownership_mask, CombatWorld.live(), [_nodes[0]], _graph)
	var removed: Array[NodeCombat] = [c]
	assert_eq(_spread().on_removed(field, removed, StatusSpread.CAUSE_DEALLOC).size(), 0, "only a kill booms")
