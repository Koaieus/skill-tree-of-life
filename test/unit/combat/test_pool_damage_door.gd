extends GutTest

## #995 (hub #994): every drain of the entity `health` pool goes through the
## ONE door, [method EntityCombat.take_pool_damage] — the core-overflow tail of
## [method NodeCombat.take_damage] and the cascade chip of
## [method EntityCombat.apply_cascade], shadow and live alike. Pinned by a
## counting subclass so a later child (the entity DoT tick, C1/C2) cannot grow
## a second deplete beside it.
##
## Fixture: core(N0) - N1 - N2. The spy has to BE the entity's slice for the
## live legs (`owner()` reads `owned_by.get_combat()` fresh), and the shadow
## legs hand-assemble a hostless spy the way [method EntityCombat.snapshot]
## does — `snapshot()` mints a bare `EntityCombat.new()`, so there is no
## public seam to substitute the class; see NOTES on #995.



class SpyCombat extends EntityCombat:
	var door_calls: Array[float] = []

	func take_pool_damage(amount: float, source: HitInstance) -> void:
		door_calls.append(amount)
		super(amount, source)


var _w: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode
var _n2: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_w = TestWorld.create(self)
	_graph = _w.graph
	_n0 = _w.add_node(&"N0")
	_n1 = _w.add_node(&"N1")
	_n2 = _w.add_node(&"N2")
	_w.link(_n0, _n1)
	_w.link(_n1, _n2)

	_alloc = _w.allocator()

	_entity = _w.add_entity("Defender")
	await get_tree().process_frame

	for n in [_n0, _n1, _n2]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _live_spy() -> SpyCombat:
	var spy := SpyCombat.new(_entity)
	_entity._combat = spy
	return spy


## A hostless spy assembled the way [method EntityCombat.snapshot] builds a
## shadow: cloned board, a mirror over the owned roster, the core shadow.
func _shadow_spy() -> SpyCombat:
	var spy := SpyCombat.new()
	spy._origin = _entity
	spy._state = _entity.state.clone()
	spy._mirror = GraphMirror.new()
	spy._mirror.graph = _graph
	for n in [_n0, _n1, _n2]:
		spy._mirror.mirror_add(n)
	spy._core = spy.shadow_for(_n0)
	_shadows.append(spy)
	return spy


func _pool_of(c: EntityCombat) -> PoolStat:
	return c.board().get_stat(&"health") as PoolStat


# ── Core overflow ────────────────────────────────────────────────────────────

func test_live_core_overflow_reaches_the_pool_through_the_door() -> void:
	var spy := _live_spy()
	var pool := _pool_of(spy)
	var pool_before := pool.current
	var core := _n0.get_combat()
	core.take_damage(core.get_max_hp() + 1.0, null)
	assert_eq(spy.door_calls.size(), 1, "one overflow → one door call")
	assert_almost_eq(spy.door_calls[0], 1.0, 0.001, "the door receives the overflow")
	assert_almost_eq(pool.current, pool_before - 1.0, 0.001, "and the pool drained by it")


func test_shadow_core_overflow_reaches_the_pool_through_the_door() -> void:
	var spy := _shadow_spy()
	var pool := _pool_of(spy)
	var pool_before := pool.current
	var core := spy.core()
	core.take_damage(core.get_max_hp() + 1.0, null)
	assert_eq(spy.door_calls.size(), 1, "one shadow overflow → one door call")
	assert_almost_eq(spy.door_calls[0], 1.0, 0.001, "the door receives the overflow")
	assert_almost_eq(pool.current, pool_before - 1.0, 0.001, "and the shadow pool drained by it")
	assert_almost_eq(_pool_of(_entity.get_combat()).current, pool_before, 0.001,
		"the live pool is untouched by a shadow")


func test_shadow_core_overflow_crossing_zero_simulates_death() -> void:
	var spy := _shadow_spy()
	var core := spy.core()
	core.take_damage(core.get_max_hp() + 999.0, null)
	assert_eq(spy.door_calls.size(), 1, "one door call")
	assert_null(spy.core(), "a shadow pool crossing 0 through the door strips the shadow's core")


# ── Cascade chip ─────────────────────────────────────────────────────────────

func test_live_cascade_chip_reaches_the_pool_through_the_door() -> void:
	var spy := _live_spy()
	var pool := _pool_of(spy)
	var pool_before := pool.current
	var entries := spy.apply_cascade([_n2.get_combat()], _alloc)
	assert_eq(entries.size(), 1, "precondition: N2 stripped")
	assert_gt(entries[0].chip, 0.0, "precondition: the strip chips")
	assert_eq(spy.door_calls.size(), 1, "one chip → one door call")
	assert_almost_eq(spy.door_calls[0], entries[0].chip, 0.001, "the door receives the chip")
	assert_almost_eq(pool.current, pool_before - entries[0].chip, 0.001, "and the pool drained by it")


func test_shadow_cascade_chip_reaches_the_pool_through_the_door() -> void:
	var spy := _shadow_spy()
	var pool := _pool_of(spy)
	var pool_before := pool.current
	var entries := spy.cascade_from(spy.shadow_for(_n2))
	assert_eq(entries.size(), 1, "precondition: shadow N2 stripped")
	assert_eq(spy.door_calls.size(), 1, "one shadow chip → one door call")
	assert_almost_eq(spy.door_calls[0], entries[0].chip, 0.001, "the door receives the chip")
	assert_almost_eq(pool.current, pool_before - entries[0].chip, 0.001, "and the shadow pool drained by it")
