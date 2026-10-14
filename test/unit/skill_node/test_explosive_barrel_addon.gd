extends GutTest

## `explosive_barrel_addon.tscn` — Explosive × Addon. Barrels stack; at the
## owner's turn start an allocated carrier tops its explosive charges up to
## its barrel count, and removing a barrel spends one charge if any. Counts
## are read off the carrier's barrels and the live status, never literals.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BARREL_SCENE := preload("res://skill_node/addons/defs/explosive_barrel_addon.tscn")
const _EXPLOSIVE := preload("res://effects/status/explosive.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = autofree(Entity.new())
	_entity.display_name = "Bomber"
	_entity.stat_board = TestBoards.flat_entity_board()
	_entity.stat_board.xp.base_value = 100000.0
	# Past the first-turn upkeep skip, so one begin_turn() runs the upkeep.
	_entity.turns_taken = 1
	_graph.add_child(_entity)
	await get_tree().process_frame


func _node(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func _barrels(n: SkillNode, count: int) -> Array[ExplosiveBarrelAddon]:
	var out: Array[ExplosiveBarrelAddon] = []
	for i in count:
		var b := _BARREL_SCENE.instantiate() as ExplosiveBarrelAddon
		n.add_child(b)
		out.append(b)
	return out


func _charges(n: SkillNode) -> float:
	return n.get_combat().get_status_power(_EXPLOSIVE.id)


func _set_charges(n: SkillNode, target: float) -> void:
	var c := n.get_combat()
	c.remove_status(_EXPLOSIVE.id)
	if target > 0.0:
		c.apply_status(_EXPLOSIVE, target)


# --- acceptance 1: turn-start refill, allocated only --------------------------

func test_allocated_carrier_refills_to_its_barrel_count_at_turn_start() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 3)
	_set_charges(n, 1.0)
	assert_eq(_charges(n), 1.0, "arranged below the barrel count")
	_entity.begin_turn()
	assert_eq(_charges(n), float(barrels.size()), "N barrels refill to N")


func test_refill_never_overshoots_a_full_carrier() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	_set_charges(n, float(barrels.size()))
	_entity.begin_turn()
	assert_eq(_charges(n), float(barrels.size()), "already full: no barrel adds on top")


func test_unallocated_carrier_never_refills() -> void:
	# An unallocated node cannot host the CLEAR-on-dealloc charge at all, so
	# the spec's "stays at 1" reads "stays at what it has: none".
	var n := _node("Loose")
	var barrels := _barrels(n, 3)
	for b in barrels:
		b.on_turn_start()
	assert_eq(_charges(n), 0.0, "only an allocated carrier refills")


# --- acceptance 2: removal spends one charge -----------------------------------

func test_removing_a_barrel_spends_one_charge() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	_set_charges(n, 2.0)
	var before := _charges(n)
	n.remove_child(barrels[0])
	barrels[0].free()
	assert_eq(_charges(n), before - 1.0, "one barrel gone, one charge gone")


func test_removing_a_barrel_from_an_empty_carrier_stays_empty() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	assert_eq(_charges(n), 0.0, "arranged empty")
	n.remove_child(barrels[0])
	barrels[0].free()
	assert_eq(_charges(n), 0.0, "never below zero")


# --- acceptance 3: decay, then refill ------------------------------------------

func test_turn_end_decay_then_turn_start_refill() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 3)
	_entity.begin_turn()
	var full := _charges(n)
	assert_eq(full, float(barrels.size()), "full after a turn start")
	n.get_combat().tick_statuses()
	var decayed := _charges(n)
	assert_lt(decayed, full, "turn-end decay spends a charge")
	_entity.begin_turn()
	assert_eq(_charges(n), full, "the next turn start refills what decayed")
