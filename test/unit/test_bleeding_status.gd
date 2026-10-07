extends GutTest

## [BleedingStatus]: an exertion grows the row by `exert_growth`, a turn tick
## pays `round_half_up(stacks × bleed_rate)` flat HP on the PRE-decay row and
## then decays on the ramp ([RampDecay]) — which an exertion resets. Expected
## series are derived from the authored knobs, never pinned as literals.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DEF := preload("res://effects/status/bleeding.tres")

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
	_entity.display_name = "Wounded"
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	_set_node_hp(10000.0)
	_fill_pool(10000.0)


func _def() -> BleedingStatus:
	return _DEF as BleedingStatus


func _combat() -> NodeCombat:
	return _node.get_combat()


func _pool() -> EntityCombat:
	return _entity.get_combat()


func _set_node_hp(hp: float) -> void:
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(hp)
	assert_gt(_node.get_current_hp(), 1000.0, "fixture: the node outlasts any series here")


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


func _fill_pool(hp: float) -> void:
	_entity.stat_board.get_stat(&"health").base_value = hp
	_health().set_current(_pool().get_max_hp())
	assert_gt(_pool().get_max_hp(), 1000.0, "fixture: the pool outlasts any series here")


## The knob model: [param turns] turns from [param stacks], exerting before
## each tick when [param exert]. Returns `[pays, rows_after]`.
func _model(stacks: float, exert: bool, turns: int) -> Array:
	var d := _def()
	var ramp := d.decay as RampDecay
	var row := stacks
	var step := 0
	var pays: Array[float] = []
	var rows: Array[float] = []
	for t in turns:
		if exert:
			row += StatusDef.round_half_up(row * (d.exert_growth - 1.0))
			step = 0
		pays.append(StatusDef.round_half_up(row * d.bleed_rate))
		row = maxf(row - (ramp.start + ramp.step * step), 0.0)
		step += 1
		rows.append(row)
	return [pays, rows]


func _tick_paying() -> float:
	var before := _node.get_current_hp()
	_combat().tick_statuses()
	return before - _node.get_current_hp()


# ── The authored def ────────────────────────────────────────────────────────

func test_the_authored_def_shape() -> void:
	var d := _def()
	assert_true(d is BleedingStatus, "bleeding.tres is a BleedingStatus")
	assert_eq(d.resistance_stat_id, &"bleeding_resistance", "the def names its resistance")
	assert_eq(d.stacks_stat_id, &"bleeding_stacks_per_hit")
	assert_true(d.decay is RampDecay, "decay is the ramp")
	assert_true(d.spread is SpillSpread, "spread is the dissipating spill")
	assert_eq(d.reapply, StatusDef.Reapply.ACCUMULATE)
	assert_eq(d.on_dealloc, StatusDef.OnDealloc.CLEAR)


# ── 1. Exerted every turn: the row grows ────────────────────────────────────

func test_five_stacks_exerted_three_turns() -> void:
	var want := _model(5.0, true, 3)
	_combat().apply_status(_def(), 5.0)
	for t in 3:
		_combat().exert()
		assert_almost_eq(_tick_paying(), want[0][t], 0.001, "turn %d pays" % t)
		assert_almost_eq(_combat().get_status_power(&"bleeding"), want[1][t], 0.001,
				"turn %d row" % t)


# ── 2. Resting: the ramp closes the wound ───────────────────────────────────

func test_five_stacks_resting_close_on_the_ramp() -> void:
	var want := _model(5.0, false, 3)
	assert_eq(want[1][2], 0.0, "the knobs close 5 stacks in three rest ticks")
	_combat().apply_status(_def(), 5.0)
	for t in 3:
		assert_almost_eq(_tick_paying(), want[0][t], 0.001, "rest turn %d pays" % t)
		assert_almost_eq(_combat().get_status_power(&"bleeding"), want[1][t], 0.001,
				"rest turn %d row" % t)
	assert_false(_combat().get_statuses().any(func(r: NodeStatus) -> bool: return r.def.id == &"bleeding"),
			"the row is gone")


# ── 3. One stack exerted every turn holds ──────────────────────────────────

func test_one_stack_exerted_every_turn_holds() -> void:
	_combat().apply_status(_def(), 1.0)
	for t in 4:
		_combat().exert()
		_combat().tick_statuses()
		assert_almost_eq(_combat().get_status_power(&"bleeding"), 1.0, 0.001, "turn %d" % t)


# ── 4. The entity host (core row) ──────────────────────────────────────────

func test_entity_host_exert_grows_and_tick_pays_the_pool() -> void:
	var d := _def()
	_pool().apply_status(d, 5.0)
	_pool().exert()
	var grown := 5.0 + StatusDef.round_half_up(5.0 * (d.exert_growth - 1.0))
	assert_almost_eq(_pool().get_status_power(&"bleeding"), grown, 0.001, "exert grows the slice")
	var before := _health().current
	_pool().tick_statuses()
	assert_almost_eq(before - _health().current, StatusDef.round_half_up(grown * d.bleed_rate), 0.001,
			"the tick pays the rate on the health pool")


# ── 5. Projection ──────────────────────────────────────────────────────────

func test_next_tick_damage_is_what_lands_and_projection_is_one_tick() -> void:
	var d := _def()
	_combat().apply_status(d, 7.0)
	var power := _combat().get_status_power(&"bleeding")
	var next := d.next_tick_damage(_combat(), power)
	assert_gt(next, 0.0, "a standing row projects damage")
	assert_almost_eq(d.projected_damage(_combat(), power), next, 0.001,
			"projection is one tick — never guesses future exertion")
	assert_almost_eq(_tick_paying(), next, 0.001, "next_tick_damage is what lands")


# ── Resistance ─────────────────────────────────────────────────────────────

func _set_res(res: float) -> void:
	_entity.stat_board.get_stat(&"bleeding_resistance").base_value = res
	assert_almost_eq(float(_combat().get_local_value(&"bleeding_resistance")), res, 0.0001,
			"bleeding_resistance arranged at %s" % res)


func test_full_resistance_takes_no_bleeding() -> void:
	_set_res(1.0)
	var hit := StatusInstance.new()
	hit.def = _def()
	hit.power = 6.0
	hit.target = _node
	hit.land_on(_combat(), CombatWorld.live())
	assert_almost_eq(hit.power, 0.0, 0.0001, "100%: the landing resolves to 0")
	assert_almost_eq(_combat().get_status_power(&"bleeding"), 0.0, 0.001, "100%: no row lands")


func test_a_standing_row_at_full_resistance_pays_nothing() -> void:
	_combat().apply_status(_def(), 6.0)
	_set_res(1.0)
	assert_almost_eq(_tick_paying(), 0.0, 0.001, "100%: the tick pays 0")
