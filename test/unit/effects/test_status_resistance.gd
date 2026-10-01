extends GutTest

## Status resistance is a live filter on the HOST at effect time (ADR 0031):
## each apply and each tick hands the def `row − cancelled`, where
## `cancelled = ⌈row × res − ½⌉` clamped to `[0, row]` (round half-down); the
## row itself decays raw. At `res >= 1` nothing lands and a standing row deals
## 0 while it still decays. The projection is the sum of what each tick
## actually lands, floored per tick through the same landing rule.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

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
	_entity.display_name = "Resistant"
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


func _combat() -> NodeCombat:
	return _node.get_combat()


func _pool() -> EntityCombat:
	return _entity.get_combat()


func _poison() -> PoisonStatus:
	var d := PoisonStatus.new()
	d.id = &"poison"
	d.resistance_stat_id = &"poison_resistance"
	d.power_max = 0.0
	d.decay = FractionDecay.new(0.5)
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.basis = HitInstance.AmountBasis.FLAT
	d.damage_per_power = 1.0
	return d


func _corruption() -> CorruptionStatus:
	var d := CorruptionStatus.new()
	d.id = &"corruption"
	d.resistance_stat_id = &"corruption_resistance"
	d.power_max = 0.0
	d.decay = FractionDecay.new(0.5)
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.damage_per_power = 0.02
	return d


func _curse() -> CurseStatus:
	var d := CurseStatus.new()
	d.id = &"curse"
	d.resistance_stat_id = &"curse_resistance"
	d.power_max = 0.0
	d.decay = FlatDecay.new(1.0)
	d.reapply = StatusDef.Reapply.ACCUMULATE
	return d


func _set_res(stat_id: StringName, res: float) -> void:
	_entity.stat_board.get_stat(stat_id).base_value = res
	assert_almost_eq(float(_combat().get_local_value(stat_id)), res, 0.0001,
			"%s arranged at %s" % [stat_id, res])


func _set_node_hp(hp: float) -> void:
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


func _health() -> PoolStat:
	return _entity.stat_board.get_stat(&"health") as PoolStat


func _fill_pool(hp: float) -> void:
	_entity.stat_board.get_stat(&"health").base_value = hp
	_health().set_current(_pool().get_max_hp())
	assert_gt(_pool().get_max_hp(), 1000.0, "the pool outlasts any series here")


func _node_hp() -> float:
	return _node.get_current_hp()


func _pool_hp() -> float:
	return _health().current


# ── The half-down table ─────────────────────────────────────────────────────

func test_the_half_down_table() -> void:
	var def := _poison()
	# [row, res, effective]
	var table := [
		[1.0, 0.01, 1.0], [1.0, 0.5, 1.0], [1.0, 0.6, 0.0],
		[3.0, 0.99, 0.0], [10.0, 0.25, 8.0], [20.0, 0.01, 20.0],
	]
	for t in table:
		_set_res(&"poison_resistance", t[1])
		assert_almost_eq(_combat().effective_status_power(def, t[0]), t[2], 0.0001,
				"%s stacks at %s%% → %s" % [t[0], t[1] * 100.0, t[2]])


func test_a_blank_resistance_id_filters_nothing() -> void:
	var def := _poison()
	def.resistance_stat_id = &""
	_set_res(&"poison_resistance", 0.9)
	assert_almost_eq(_combat().effective_status_power(def, 10.0), 10.0, 0.0001)


# ── Poison ticks through the filter; the row decays raw ─────────────────────

func test_poison_at_1_percent_lands_the_full_20() -> void:
	_set_node_hp(10000.0)
	_set_res(&"poison_resistance", 0.01)
	_combat().apply_status(_poison(), 20.0)
	var before := _node_hp()
	_combat().tick_statuses()
	assert_almost_eq(before - _node_hp(), 20.0, 0.001, "1% never curbs a 20-row")


func test_poison_at_25_percent_lands_15_and_the_row_halves_raw() -> void:
	_set_node_hp(10000.0)
	_set_res(&"poison_resistance", 0.25)
	_combat().apply_status(_poison(), 20.0)
	var before := _node_hp()
	_combat().tick_statuses()
	assert_almost_eq(before - _node_hp(), 15.0, 0.001, "20 − ⌈5 − ½⌉ = 15")
	assert_almost_eq(_combat().get_status_power(&"poison"), 10.0, 0.001,
			"the row decays from its full, unresisted 20")


func test_resistance_dropped_between_ticks_counts_the_full_row() -> void:
	_set_node_hp(10000.0)
	_set_res(&"poison_resistance", 0.5)
	_combat().apply_status(_poison(), 20.0)
	_combat().tick_statuses()
	assert_almost_eq(_combat().get_status_power(&"poison"), 10.0, 0.001, "raw halving")
	_set_res(&"poison_resistance", 0.0)
	var before := _node_hp()
	_combat().tick_statuses()
	assert_almost_eq(before - _node_hp(), 10.0, 0.001, "no resistance: the whole row counts")


# ── 100% blocks landing; a standing row deals 0 and still decays ────────────

func test_full_resistance_resolves_a_landing_to_zero_and_no_row() -> void:
	_set_res(&"poison_resistance", 1.0)
	var hit := StatusInstance.new()
	hit.def = _poison()
	hit.power = 3.0
	hit.target = _node
	hit.land_on(_combat(), CombatWorld.live())
	assert_true(hit.power_resolved, "resolved on the authority")
	assert_almost_eq(hit.power, 0.0, 0.0001, "blocked: the record carries 0")
	assert_almost_eq(hit.effective_amount, 0.0, 0.0001)
	assert_eq(_combat().get_statuses().size(), 0, "no row appears")


func test_a_standing_row_at_full_resistance_deals_nothing_but_decays() -> void:
	_set_node_hp(10000.0)
	_set_res(&"poison_resistance", 0.0)
	_combat().apply_status(_poison(), 20.0)
	_set_res(&"poison_resistance", 1.0)
	var before := _node_hp()
	_combat().tick_statuses()
	assert_almost_eq(before - _node_hp(), 0.0, 0.001, "100%: the tick deals 0")
	assert_almost_eq(_combat().get_status_power(&"poison"), 10.0, 0.001, "and still decays")


# ── A planting def receives the filtered power ──────────────────────────────

func test_curse_at_50_percent_plants_the_effective_after() -> void:
	var def := _curse()
	_set_res(&"curse_resistance", 0.5)
	_combat().apply_status(def, 10.0)
	_combat().tick_statuses()
	var m: StatModifier = def._find(_combat())
	assert_not_null(m, "the curse is planted")
	var expected := _combat().effective_status_power(def, 9.0)
	assert_almost_eq(expected, 5.0, 0.0001, "9 − ⌈4.5 − ½⌉ = 5")
	assert_almost_eq(m.value, expected, 0.0001, "the modifier is effective_power(after)")


# ── Fall-through: an entity-hosted row reads the ENTITY's resistance ────────

func test_an_entity_hosted_poison_row_reads_the_entitys_resistance() -> void:
	_fill_pool(10000.0)
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.25
	var local := StatModifier.new()
	local.stat_id = &"poison_resistance"
	local.operation = StatModifier.Operation.ADD_BASE
	local.value = 0.65
	_combat().add_local_modifier(local)
	assert_almost_eq(float(_combat().get_local_value(&"poison_resistance")), 0.9, 0.0001,
			"the node reads 0.9 locally")
	_pool().apply_status(_poison(), 20.0)
	var before := _pool_hp()
	_pool().tick_statuses()
	assert_almost_eq(before - _pool_hp(), 15.0, 0.001,
			"the entity's 25%, never the node's 90%")


# ── Projection parity: the bar equals reality ───────────────────────────────

const _RESISTANCES: Array[float] = [0.0, 0.01, 0.25, 1.0]
const _POWERS: Array[float] = [1.0, 12.7, 20.0]


## Ticks [param host] to empty, returning `[projected, landed, first_tick,
## next_tick_damage]`, [param hp] reading the pool that host drains.
func _run_to_empty(host, def: StatusDef, power: float, hp: Callable) -> Array[float]:
	host.release_statuses()
	host.apply_status(def, power)
	var projected: float = host.projected_status_damage()
	var next: float = def.next_tick_damage(host, host.get_status_power(def.id))
	var landed := 0.0
	var first := -1.0
	var guard := 0
	while host.get_status_power(def.id) > 0.0 and guard < 50:
		var before: float = hp.call()
		host.tick_statuses()
		var drop: float = before - hp.call()
		if first < 0.0:
			first = drop
		landed += drop
		guard += 1
	return [projected, landed, first, next]


func _assert_parity(label: String, host, def: StatusDef, hp: Callable, refill: Callable) -> void:
	for res in _RESISTANCES:
		_entity.stat_board.get_stat(def.resistance_stat_id).base_value = res
		for power in _POWERS:
			refill.call()
			var r := _run_to_empty(host, def, power, hp)
			var tag := "%s res %s power %s" % [label, res, power]
			assert_almost_eq(r[0], r[1], 0.0001, "%s: projected == landed" % tag)
			assert_almost_eq(r[3], r[2], 0.0001, "%s: next_tick_damage == the first tick" % tag)


func test_projection_parity_flat_poison_on_a_node() -> void:
	_assert_parity("node poison", _combat(), _poison(), _node_hp,
			func() -> void: _set_node_hp(10000.0))


func test_projection_parity_corruption_on_a_node() -> void:
	# An odd max hp so the per-tick PERCENT_MAX products are fractional.
	_assert_parity("node corruption", _combat(), _corruption(), _node_hp,
			func() -> void: _set_node_hp(1237.0))


func test_projection_parity_poison_on_the_entity_pool() -> void:
	_assert_parity("entity poison", _pool(), _poison(), _pool_hp,
			func() -> void: _fill_pool(10000.0))
