extends GutTest

## EntityCombat.snapshot() (#498 step 2 — see docs/domain/attack-timeline.md).
## Fixture: core(N0) - N1 - N2, N1 - N3, so N1 is a cut vertex — removing it
## islands {N2, N3} from the core. Same shape test_entity_death.gd uses.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode  # cut vertex
var _n2: SkillNode
var _n3: SkillNode
var _events_fired: int = 0
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_events_fired = 0
	_shadows = []

	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_n2 = _new_node("N2")
	_n3 = _new_node("N3")
	_add_edge(_n0, _n1)
	_add_edge(_n1, _n2)
	_add_edge(_n1, _n3)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame  # entity._ready: navigator wiring

	for n in [_n0, _n1, _n2, _n3]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0

	for s in [Events.skill_node_damaged, Events.skill_node_healed, Events.skill_node_depleted,
			Events.entity_dying, Events.entity_died, Events.entity_death_shown]:
		s.connect(_count_event)


func after_each() -> void:
	for s in [Events.skill_node_damaged, Events.skill_node_healed, Events.skill_node_depleted,
			Events.entity_dying, Events.entity_died, Events.entity_death_shown]:
		if s.is_connected(_count_event):
			s.disconnect(_count_event)
	for s in _shadows:
		s.free_shadow()


func _count_event(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_events_fired += 1


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _owned_count() -> int:
	var c := 0
	for n in [_n0, _n1, _n2, _n3]:
		if n.owned_by == _entity:
			c += 1
	return c


# ── Host invariant ───────────────────────────────────────────────────────────

func test_snapshot_host_is_null() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	assert_null(shadow.host, "a snapshot must be a hostless shadow")
	for n in shadow.owned():
		assert_null(n.host, "every snapshotted NodeCombat must also be hostless")


func test_simulated_kill_emits_nothing_on_events() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_n1: NodeCombat = shadow._shadow_by_real[_n1]
	shadow_n1.take_damage(999999.0, null)
	assert_eq(_events_fired, 0, "a shadow kill must never reach the Events bus")
	# And the real world is untouched.
	assert_eq(_n1.owned_by, _entity, "the real node must still be owned")
	assert_eq(_owned_count(), 4, "the real territory must be unaffected by a shadow kill")


# ── Never cache owner/board (live) ──────────────────────────────────────────

func test_live_slice_never_caches_ownership() -> void:
	var combat := _n1.get_combat()
	assert_true(combat.is_allocated(), "precondition: N1 starts owned")
	# AllocationSystem writes owned_by directly — the slice has no idea this
	# happened, and must still read it correctly on the very next call.
	_alloc.force_deallocate(_n1)
	assert_false(combat.is_allocated(), "the slice must read the deallocation with nobody telling it")


# ── Islanding parity ─────────────────────────────────────────────────────────

func test_shadow_kill_islands_the_same_set_as_the_live_navigator() -> void:
	var ground_truth: Array[SkillNode] = _entity.navigator.nodes_islanded_by_removing(_n1, _n0)
	assert_eq(ground_truth.size(), 2, "precondition: removing the cut vertex islands N2 + N3")

	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_n1: NodeCombat = shadow._shadow_by_real[_n1]
	shadow_n1.take_damage(999999.0, null)

	var still_owned := shadow.owned()
	assert_false(still_owned.has(shadow_n1), "the killed node itself must be stripped")
	for real in ground_truth:
		var shadow_equiv: NodeCombat = shadow._shadow_by_real[real]
		assert_false(still_owned.has(shadow_equiv),
				"%s must be islanded on the shadow exactly as it is live" % real.name)
	assert_true(still_owned.has(shadow._shadow_by_real[_n0]), "the core survives — only N1's arm islands")

	# The live world never moved.
	assert_eq(_owned_count(), 4, "a shadow-resolved kill must not touch real ownership")


# ── Recursive entity-death strip ────────────────────────────────────────────

func test_core_overflow_on_shadow_strips_every_owned_node() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	(shadow.board().get_stat(&"health") as PoolStat).set_current(1.0)
	var shadow_core: NodeCombat = shadow._shadow_by_real[_n0]
	shadow_core.take_damage(999999.0, null)

	assert_true(shadow.owned().is_empty(), "chipping health to 0 must strip the whole shadow territory")
	# Real entity is completely untouched.
	assert_eq(_owned_count(), 4, "the real entity must still own everything")
	assert_false(_entity.is_dead, "the real entity must not have died")
	assert_eq(_events_fired, 0, "no Events traffic for a shadow's simulated death")


# ── Teardown collects the cloned boards (#514) ──────────────────────────────

func test_free_shadow_releases_every_board_it_cloned() -> void:
	var shadow := _entity.get_combat().snapshot()
	var entity_board := shadow.board()
	var node_boards: Array[NodeStatBoard] = []
	for n in shadow.owned():
		node_boards.append(n.board())
	assert_gt(node_boards.size(), 0, "fixture sanity: the shadow owns node boards to release")
	# Non-vacuity: the assertions below only mean something if these were wired.
	assert_false(entity_board._localized.is_empty(),
			"fixture sanity: the entity board's formula intrinsics were localized")
	assert_not_null(entity_board.get_stat(&"node_health")._board,
			"fixture sanity: the stat backpointer that forms the cycle is set")

	shadow.free_shadow()

	assert_null(entity_board.get_stat(&"node_health")._board,
			"the entity board must be RELEASED, not just dropped — a Stat backpointing "
			+ "at its board is a RefCounted cycle nothing collects")
	assert_true(entity_board._localized.is_empty(), "and left unwired, not merely collectable")
	for b in node_boards:
		for id in b.get_stat_ids():
			assert_null(b.get_stat(id)._board,
					"every owned node's board must be released by the same teardown, "
					+ "never left to a caller to remember")


func test_snapshot_and_free_shadow_leaks_nothing() -> void:
	var live := _entity.get_combat()
	for i in 5:  # warm up
		live.snapshot().free_shadow()
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 50:
		var s := live.snapshot()
		s.free_shadow()
		s = null
	var leaked := (Performance.get_monitor(Performance.OBJECT_COUNT) - before) / 50.0
	assert_almost_eq(leaked, 0.0, 1.0,
			"an AI rollout takes a shadow per candidate and drops it; a snapshot "
			+ "that leaks turns one turn into hundreds of stranded boards")


# ── #518: one cascade driver — the shadow charges what the live path charges ──


func _sp_used(board: StatBoard) -> Dictionary:
	var sp := board.get_stat(&"skill_points") as SkillPointStat
	return {"wounded": sp.wounded, "used": sp.used}


func _health(board: StatBoard) -> float:
	return (board.get_stat(&"health") as PoolStat).current


## Scope item 3. Before #518 a shadow's cascade stripped ownership and topology
## and charged NOTHING, so a simulated attack could shatter the defender's
## territory while reporting zero attrition — and since entity `health` only
## ever moves via core overflow or this chip, the shadow's answer to "did that
## advance me toward killing them" was always no.
func test_shadow_cascade_charges_the_same_wound_and_chip_as_the_live_path() -> void:
	var live_board := _entity.stat_board
	var before_wounded: int = _sp_used(live_board)["wounded"]
	var before_health := _health(live_board)

	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_board := shadow.board()
	# The clone starts where the live board is, or the comparison is vacuous.
	assert_eq(_sp_used(shadow_board)["wounded"], before_wounded,
			"a fresh shadow board must start at the live wound count")
	assert_almost_eq(_health(shadow_board), before_health, 0.01,
			"a fresh shadow board must start at the live health")

	# Kill the cut vertex on the SHADOW: N1 leaves, islanding N2 and N3 — three
	# nodes cascade, so three wounds and three chips.
	var shadow_n1: NodeCombat = shadow._shadow_by_real[_n1]
	var entries := shadow.cascade_from(shadow_n1)

	assert_eq(entries.size(), 3, "N1 plus the two nodes it islands")
	var total_wound := 0
	var total_chip := 0.0
	for e in entries:
		assert_true(e.allocation_level >= 1, "the pre-strip fill is floored at 1")
		total_wound += e.wound
		total_chip += e.chip
	assert_gt(total_wound, 0, "a cascade must wound")
	assert_gt(total_chip, 0.0, "a cascade must chip")

	assert_eq(_sp_used(shadow_board)["wounded"], before_wounded + total_wound,
			"the shadow board must carry the wounds its own cascade charged")
	assert_almost_eq(_health(shadow_board), before_health - total_chip, 0.01,
			"the shadow board must carry the chip its own cascade charged")
	# The live world is untouched — the whole point of a shadow.
	assert_eq(_sp_used(live_board)["wounded"], before_wounded,
			"a simulated cascade must not wound the real entity")
	assert_almost_eq(_health(live_board), before_health, 0.01,
			"a simulated cascade must not chip the real entity")
	assert_eq(_owned_count(), 4, "a simulated cascade must not strip a real node")


## The parity claim itself, run both ways on the same fixture: the numbers the
## shadow charges are the numbers the live cascade charges. This is what makes
## the driver ONE implementation rather than two that happen to agree today.
func test_shadow_and_live_cascade_charge_identical_numbers() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_board := shadow.board()
	var sim_wound_before: int = _sp_used(shadow_board)["wounded"]
	var sim_health_before := _health(shadow_board)
	shadow.cascade_from(shadow._shadow_by_real[_n1])
	var sim_wound: int = _sp_used(shadow_board)["wounded"] - sim_wound_before
	var sim_chip := sim_health_before - _health(shadow_board)

	# Mounted HERE, not in `before_each`: BattleSystem listens on the GLOBAL
	# `Events.skill_node_depleted`, so a fixture-wide one would put a live
	# cascade behind every other test in this file. This is the only test that
	# wants the real bus path.
	var battle := BattleSystem.new()
	battle.graph = _graph
	battle.allocation_system = _alloc
	add_child_autofree(battle)

	var live_board := _entity.stat_board
	var live_wound_before: int = _sp_used(live_board)["wounded"]
	var live_health_before := _health(live_board)
	# The real path, through the real bus: deplete N1's HP for real.
	_n1.take_damage(100000.0, null)
	var live_wound: int = _sp_used(live_board)["wounded"] - live_wound_before
	var live_chip := live_health_before - _health(live_board)

	assert_eq(sim_wound, live_wound,
			"simulated and real cascades must wound identically")
	assert_almost_eq(sim_chip, live_chip, 0.01,
			"simulated and real cascades must chip identically")


## Scope item 4's input: the driver reports what it stripped, per node, with the
## PRE-strip fill. A read after `force_deallocate` returns 0 (#337) — that
## collapse is the reason the entry exists rather than a recomputation.
func test_cascade_entries_name_the_nodes_and_carry_the_pre_strip_fill() -> void:
	var driver := _entity.get_combat()
	var n1_fill := _n1.allocation_level
	assert_gt(n1_fill, 0, "fixture sanity: N1 is allocated before the cascade")
	var entries := driver.cascade_from(_n1.get_combat(), _alloc)

	var by_node: Dictionary[SkillNode, DeallocEntry] = {}
	for e in entries:
		by_node[e.node] = e
	assert_true(by_node.has(_n1), "the depleted node is in its own cascade")
	assert_true(by_node.has(_n2), "N2 islands off N1")
	assert_true(by_node.has(_n3), "N3 islands off N1")
	assert_false(by_node.has(_n0), "the core stays — it is the anchor")
	assert_eq(by_node[_n1].allocation_level, n1_fill,
			"the entry carries the fill from BEFORE the strip, not the zeroed one")
	assert_eq(_n1.allocation_level, 0,
			"fixture sanity: the live fill really does collapse to 0 after the strip")


## Whole-entity death strips through the same driver but charges nothing —
## matching `AllocationSystem.deallocate_all_owned`, which does not further
## attrit an entity already at 0 health. A `charge` that defaulted the other way
## would invent a divergence rather than remove one.
func test_simulated_entity_death_strips_without_charging() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var board := shadow.board()
	var wounded_before: int = _sp_used(board)["wounded"]
	var entries := shadow.simulate_entity_death()
	assert_eq(entries.size(), 4, "every owned node leaves, core included")
	assert_eq(shadow.owned().size(), 0, "nothing is owned after a death sweep")
	assert_eq(_sp_used(board)["wounded"], wounded_before,
			"a death sweep must not wound — the entity is already dead")
