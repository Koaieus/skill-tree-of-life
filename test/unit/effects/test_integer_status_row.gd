extends GutTest

## ADR 0032: a status row is an integer stack count. A fraction is rounded
## where it is MINTED — the landing fold rounds half-up
## ([method StatusDef.stacks_per_hit]), a fractional decay keeps
## `⌊S · (1 − f)⌋` ([method FractionDecay.decayed]) — never at the store.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://effects/status/poison.tres")
const _CORRUPTION := preload("res://effects/status/corruption.tres")
const _CURSE := preload("res://effects/status/curse.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = autofree(Entity.new())
	_entity.display_name = "Host"
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	# A deep pool so a DoT tick never kills the host mid-assert.
	_entity.stat_board.get_stat(&"node_health").base_value = 10000.0
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(10000.0)


func _combat() -> NodeCombat:
	return _node.get_combat()


func _board_with_increase(pct: float) -> StatBoard:
	var board := TestBoards.flat_entity_board()
	var m := StatModifier.new()
	m.stat_id = &"poison_stacks_per_hit"
	m.operation = StatModifier.Operation.INCREASE
	m.value = pct
	board.add_modifier(m)
	return board


func _accumulating(decay: StatusDecay) -> StatusDef:
	var d := StatusDef.new()
	d.id = &"plain"
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.power_max = 0.0
	d.decay = decay
	return d


# ── The landing fold rounds half-up, once ────────────────────────────────────

func test_the_fold_rounds_half_up() -> void:
	assert_eq(_POISON.stacks_per_hit(_board_with_increase(50.0), 1.0), 2.0, "1 × 1.5 → 2")
	assert_eq(_POISON.stacks_per_hit(_board_with_increase(7.0), 1.0), 1.0, "1 × 1.07 → 1")
	assert_eq(_POISON.stacks_per_hit(_board_with_increase(25.0), 2.0), 3.0,
			"2 × 1.25 = 2.5 ties to the attacker → 3")
	assert_eq(_POISON.stacks_per_hit(_board_with_increase(17.0), 3.0), 4.0, "3 × 1.17 → 4")


func test_the_fold_rounds_even_without_a_board() -> void:
	assert_eq(_POISON.stacks_per_hit(null, 1.5), 2.0, "null board still lands a whole count")


# ── Fractional decay keeps the floor and reaches 0 ───────────────────────────

func _assert_floor_kept(f: float, start: int) -> void:
	var decay := FractionDecay.new(f)
	var s := float(start)
	var guard := 0
	while s > 0.0 and guard < 100:
		var next := decay.decayed(s)
		assert_eq(next, floorf(s * (1.0 - f) + 0.000001),
				"f %s: %s keeps ⌊S(1−f)⌋" % [f, s])
		assert_lt(next, s, "f %s: strictly shrinks from %s" % [f, s])
		s = next
		guard += 1
	assert_eq(s, 0.0, "f %s from %d reaches 0" % [f, start])


func test_fraction_decay_keeps_the_floor_and_reaches_zero() -> void:
	_assert_floor_kept(0.2, 3)
	_assert_floor_kept(0.5, 10)
	_assert_floor_kept(0.25, 8)
	assert_eq(FractionDecay.new(0.2).decayed(3.0), 2.0, "3 × 0.8 = 2.4 keeps 2")


# ── Every writer leaves an int on the row ────────────────────────────────────

func test_every_writer_leaves_an_int_row() -> void:
	var d := _accumulating(FractionDecay.new(0.5))
	_combat().apply_status(d, 5.0)
	assert_eq(typeof(_combat().get_statuses()[0].power), TYPE_INT, "after apply_status")
	_combat().adjust_status_power(d, 2.0)
	assert_eq(typeof(_combat().get_statuses()[0].power), TYPE_INT, "after adjust_status_power")
	_combat().tick_statuses()
	assert_eq(typeof(_combat().get_statuses()[0].power), TYPE_INT, "after a tick")
	assert_eq(_combat().get_statuses()[0].power, 3, "7 halved keeps 3")


# ── The shipped decay shapes ─────────────────────────────────────────────────

func test_poison_loses_exactly_one_stack_per_tick() -> void:
	_combat().apply_status(_POISON, 10.0)
	for expected in [9, 8, 7]:
		_combat().tick_statuses()
		assert_eq(_combat().get_status_power(&"poison"), float(expected), "10 → … → %d" % expected)


func test_corruption_does_not_decay() -> void:
	_combat().apply_status(_CORRUPTION, 10.0)
	_combat().tick_statuses()
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"corruption"), 10.0, "no decay slot")


func test_curse_loses_exactly_one_stack_per_tick() -> void:
	_combat().apply_status(_CURSE, 4.0)
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"curse"), 3.0, "4 → 3")
