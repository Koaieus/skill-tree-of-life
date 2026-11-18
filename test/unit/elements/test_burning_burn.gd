extends GutTest

## Burning burns its holder each world turn ([method CombatWorld.burn_terrain]):
## `burn_per_excess × (Heat − T)` TRUE damage through [method DotTick.mint], no
## attack record, side-blind, only on an allocated node; the overflow band burns
## by the whole excess. Fixture: X — Y — Z, each X/Z a leaf hung off hub Y,
## plus far-off cores for the holders (so a burn never lands on a core).

const _TERRAIN_SETTLE := "res://combat/terrain/terrain_settle.gd"

var _w: TestWorld
var _graph: Graph
var _x: SkillNode
var _y: SkillNode
var _z: SkillNode
var _fire: Element
var _a: Entity
var _b: Entity
## Per node: every `damaged` the node took, as [amount, source].
var _hits: Dictionary = {}


func before_each() -> void:
	CombatWorld.reset_live()
	_hits = {}
	_w = TestWorld.create(self)
	_graph = _w.graph
	_x = _w.add_node(&"X", Vector2(0, 0))
	_y = _w.add_node(&"Y", Vector2(200, 0))
	_z = _w.add_node(&"Z", Vector2(400, 0))
	_w.link(_x, _y)
	_w.link(_y, _z)
	var core_a := _w.add_node(&"CA", Vector2(-5000, 0))
	var core_b := _w.add_node(&"CB", Vector2(5000, 0))
	_a = _w.add_entity("A")
	_b = _w.add_entity("B")
	await get_tree().process_frame
	_w.allocate(_a, [core_a])
	_w.allocate(_b, [core_b])
	_fire = ElementRoster.shared().by_id(&"fire")
	for n: SkillNode in [_x, _y, _z]:
		_hits[n] = []
		n.damaged.connect(_on_damaged.bind(n))


func after_each() -> void:
	CombatWorld.reset_live()


func _on_damaged(amount: float, source: HitInstance, n: SkillNode) -> void:
	_hits[n].append([amount, source])


func _c(n: SkillNode) -> NodeCombat:
	return n.get_combat()


## [param n]'s t set to its T + [param excess].
func _heat(n: SkillNode, excess: int) -> void:
	var c := _c(n)
	c.add_terrain(_fire, c.terrain_threshold() + excess - c.terrain_t())


func _burned(n: SkillNode) -> float:
	var sum := 0.0
	for h: Array in _hits[n]:
		sum += h[0]
	return sum


func _band(index: int) -> ElementBand:
	return _fire.bands[index]


func test_an_allocated_burning_node_burns_by_the_excess_as_true_damage_no_record() -> void:
	_w.allocate(_a, [_x])
	_heat(_x, 3)
	var per := _band(0).burn_per_excess
	assert_gt(per, 0.0, "Fire's Burning band burns")
	assert_gt(_c(_x).get_max_hp(), 3.0 * per, "headroom: the hit is never clamped")
	CombatWorld.live().burn_terrain()
	assert_eq(_hits[_x].size(), 1, "one burn tick")
	assert_almost_eq(_burned(_x), 3.0 * per, 0.001, "burn_per_excess × excess")
	if _hits[_x].size() == 1:
		var dmg := _hits[_x][0][1] as DamageInstance
		assert_not_null(dmg, "a DamageInstance")
		if dmg != null:
			assert_eq(dmg.type, DamageInstance.Type.TRUE, "TRUE damage")
			assert_null(dmg.attacker, "no attacker: a world effect")
			assert_null(dmg.source, "no record behind it")


func test_the_burn_scales_with_the_excess() -> void:
	_w.allocate(_a, [_x])
	_heat(_x, 1)
	CombatWorld.live().burn_terrain()
	var one := _burned(_x)
	_hits[_x].clear()
	_heat(_x, 4)
	CombatWorld.live().burn_terrain()
	assert_gt(one, 0.0)
	assert_almost_eq(_burned(_x), 4.0 * one, 0.001, "∝ the excess")


func test_an_unallocated_burning_node_takes_nothing() -> void:
	_heat(_x, 3)
	CombatWorld.live().burn_terrain()
	assert_eq(_hits[_x].size(), 0, "no holder, no burn")


func test_the_holders_camp_does_not_matter() -> void:
	_w.allocate(_a, [_x])
	_w.allocate(_b, [_z])
	_heat(_x, 2)
	_heat(_z, 2)
	CombatWorld.live().burn_terrain()
	assert_almost_eq(_burned(_x), _burned(_z), 0.001, "side-blind")
	assert_gt(_burned(_z), 0.0)


func test_heat_at_or_below_t_burns_nothing() -> void:
	_w.allocate(_a, [_x])
	_heat(_x, 0)
	assert_gt(_c(_x).terrain_t(), 0, "sanity: Heat, just not past T")
	CombatWorld.live().burn_terrain()
	assert_eq(_hits[_x].size(), 0)


func test_a_world_turn_burns_by_the_pre_diffusion_excess() -> void:
	var tm: TurnManager = autofree(TurnManager.new())
	tm.entity_root = _graph
	add_child(tm)
	tm.terrain_steps_per_world_turn = 1
	var turns := [0]
	tm.world_turn_ended.connect(func() -> void: turns[0] += 1)
	_w.allocate(_a, [_x])
	_heat(_x, 1)
	tm.start_turn(_a)
	for _i in 8:
		if turns[0] > 0:
			break
		tm.end_turn()
	assert_eq(turns[0], 1, "sanity: one world turn")
	assert_true(_c(_x).terrain_t() <= _c(_x).terrain_threshold(),
			"the diffusion took X to T or below")
	assert_almost_eq(_burned(_x), _band(0).burn_per_excess * 1.0, 0.001,
			"burned by the excess before the diffusion")


func test_terrain_settle_holds_no_dot_tick() -> void:
	var src := FileAccess.get_file_as_string(_TERRAIN_SETTLE)
	assert_gt(src.length(), 0, "sanity: the file read")
	assert_false(src.contains("DotTick"), "the settle stays pure: the burn is not in it")


func test_death_dealloc_and_retake_leave_t_and_the_burn_resumes() -> void:
	_w.allocate(_a, [_x])
	_heat(_x, 2)
	var t := _c(_x).terrain_t()
	_a.die()
	await get_tree().process_frame
	assert_eq(_c(_x).terrain_t(), t, "a holder's death leaves t")
	TestWorld.allocator_for(_graph).force_deallocate(_x)
	assert_false(_x.is_allocated(), "sanity: dealloced")
	assert_eq(_c(_x).terrain_t(), t, "a dealloc leaves t")
	CombatWorld.live().burn_terrain()
	assert_eq(_hits[_x].size(), 0, "nobody holds it: no burn")
	_w.allocate(_b, [_x])
	assert_eq(_c(_x).terrain_t(), t, "a retake leaves t")
	CombatWorld.live().burn_terrain()
	assert_almost_eq(_burned(_x), 2.0 * _band(0).burn_per_excess, 0.001,
			"the burn resumes for the next holder")


func test_the_burn_order_is_the_stable_id_order_never_the_index_order() -> void:
	_w.allocate(_a, [_x])
	_w.allocate(_b, [_z])
	var order: Array = []
	for n: SkillNode in [_x, _z]:
		n.damaged.connect(func(_amt: float, _src: HitInstance) -> void: order.append(n))
	_heat(_x, 1)
	_heat(_z, 1)
	CombatWorld.live().burn_terrain()
	var first := order.duplicate()
	for n: SkillNode in [_x, _z]:
		_c(n).add_terrain(_fire, -_c(n).terrain_t())
	order.clear()
	_heat(_z, 1)
	_heat(_x, 1)
	CombatWorld.live().burn_terrain()
	assert_eq(first.size(), 2, "sanity: both burned")
	assert_eq(order, first, "the same order whichever was heated first")


func test_the_overflow_band_burns_by_the_whole_excess() -> void:
	assert_eq(_band(1).burn_per_excess, _band(0).burn_per_excess,
			"the overflow band burns as Burning does")
	_w.allocate(_a, [_x])
	var c := _c(_x)
	var tt := c.terrain_threshold()
	var cap := c.terrain_cap()
	assert_gt(cap, tt, "sanity: the cap sits above T")
	c.add_terrain(_fire, cap + 2 - c.terrain_t())
	assert_eq(c.terrain_band(_fire), _band(1), "sanity: in the overflow band")
	assert_gt(c.get_max_hp(), float(cap + 2 - tt) * _band(1).burn_per_excess, "headroom")
	CombatWorld.live().burn_terrain()
	assert_almost_eq(_burned(_x), float(cap + 2 - tt) * _band(1).burn_per_excess, 0.001,
			"Heat − T, never Heat − k × T")
