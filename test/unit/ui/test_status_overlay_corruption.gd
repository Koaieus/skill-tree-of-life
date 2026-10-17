extends GutTest

## [StatusOverlay]'s corruption layer: N blips, N pending chunks worth what a
## degree-loss pop deals, and while critical (`N == T − 1`) a ghost chunk worth
## the extra a landing stack's pop adds. Reads the overlay's model
## ([member StatusOverlay.chunks] / `ghost` / `blips` / `critical`), never pixels.
##
## Board: N0 with three Mine neighbours (N1 is the core) → `T = 3 + burn 1 +
## keep 0 = 4`. Max hp 100 on a 100 px bar with a full fill: 1 px per HP, and
## `X·maxHP = 2` per unit of threshold.

const _OVERLAY_SCENE := preload("res://ui/status_overlay/status_overlay.tscn")
const _CORRUPTION: CorruptionStatus = preload("res://effects/status/corruption.tres")

const _HP := 100.0

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	var world := TestWorld.create(self)
	_graph = world.graph
	_alloc = world.allocator()
	_entity = world.add_entity("", TestBoards.flat_entity_board())
	_nodes = world.build([[0, 1], [0, 2], [0, 3]])
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[1])
	_entity.core_location = _nodes[1]
	for i in [0, 2, 3]:
		_alloc.force_allocate(_entity, _nodes[i])
	_entity.stat_board.get_stat(&"node_health").base_value = _HP
	_nodes[0].get_max_hp()
	(_nodes[0].node_board.get_stat(&"node_health") as PoolStat).set_current(_HP)


func _host() -> NodeCombat:
	return _nodes[0].get_combat()


func _spread() -> SandpileSpread:
	return _CORRUPTION.spread as SandpileSpread


func _overlay() -> StatusOverlay:
	var frame := Control.new()
	frame.size = Vector2(100, 10)
	add_child_autofree(frame)
	var o := _OVERLAY_SCENE.instantiate() as StatusOverlay
	frame.add_child(o)
	o.bind(_host(), _nodes[0].statuses_changed)
	o.set_fill(_HP, _HP)
	return o


func _width(rects: Array[Rect2]) -> float:
	var w := 0.0
	for r in rects:
		w += r.size.x
	return w


# ── 1. Under T − 1: N blips, chunks = the degree-loss pop, no ghost ─────────

func test_under_critical_draws_n_blips_and_the_degree_loss_pop() -> void:
	assert_eq(_spread().threshold_of(_host()), 4, "fixture: T = 3 Mine neighbours + burn 1")
	var o := _overlay()
	_host().apply_status(_CORRUPTION, 2.0)
	assert_eq(o.blips.size(), 2, "one blip per stack")
	assert_eq(o.chunks.size(), 2, "one chunk per stack")
	assert_almost_eq(_width(o.chunks), _CORRUPTION.burst_amount(_host(), 1, 2), 0.01,
			"chunks = what a pop at T lowered to N deals")
	assert_almost_eq(o.chunks[0].end.x, 100.0, 0.01, "chunks start at the fill tip")
	assert_false(o.critical, "N = T − 2 is not critical")
	assert_false(o.ghost.has_area(), "no ghost under critical")


# ── 2. At T − 1: ghost = stack pop − solid, and that is what lands ─────────

func test_critical_ghost_is_the_extra_a_landing_stack_deals() -> void:
	assert_eq(_spread().threshold_of(_host()), 4, "fixture: T = 4")
	var o := _overlay()
	_host().apply_status(_CORRUPTION, 3.0)
	assert_true(o.critical, "N = T − 1 is critical")
	assert_eq(o.chunks.size(), 3, "N solid chunks")
	var solid := _width(o.chunks)
	assert_almost_eq(solid, _CORRUPTION.burst_amount(_host(), 1, 3), 0.01, "solid = degree-loss pop")
	assert_gt(o.ghost.size.x, 0.0, "fixture: the ghost has width at this max hp")
	assert_almost_eq(o.ghost.size.x, _CORRUPTION.burst_amount(_host(), 1, 4) - solid, 0.01,
			"ghost = stack pop − solid")
	var ghost_w := o.ghost.size.x
	var before := _nodes[0].get_current_hp()
	_host().apply_status(_CORRUPTION, 1.0)
	CombatWorld.live().flush_removals()
	assert_almost_eq(before - _nodes[0].get_current_hp(), solid + ghost_w, 0.01,
			"a landed stack's pop costs solid + ghost")


# ── 3. A neighbour leaves: T drops with no status change, overlay re-reads ──

func test_neighbour_dealloc_rereads_threshold_and_turns_critical() -> void:
	var o := _overlay()
	_host().apply_status(_CORRUPTION, 2.0)
	assert_false(o.critical, "fixture: T − 2 before")
	_alloc.force_deallocate(_nodes[3])
	assert_eq(_spread().threshold_of(_host()), 3, "fixture: the dealloc lowered T")
	assert_true(o.critical, "the overlay re-read T without a statuses_changed")
	assert_gt(o.ghost.size.x, 0.0, "and grew its ghost")


# ── 4. Mid-settle N ≥ T: legal, drawn as read ─────────────────────────────

func test_transient_pile_at_or_over_threshold_draws_n_blips() -> void:
	var o := _overlay()
	_host().apply_status(_CORRUPTION, 5.0)
	assert_eq(o.blips.size(), 5, "N blips, never clamped to T − 1")
	assert_false(o.critical, "over T is not the critical T − 1")
	assert_false(o.ghost.has_area(), "no ghost")
