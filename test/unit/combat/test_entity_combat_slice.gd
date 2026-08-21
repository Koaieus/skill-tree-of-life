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


## Scope item 4: the hit that killed a node carries what that cost, and it is
## the SAME loop's output on both paths. A hit exposing damage totals but not
## deallocations does not expose the attrition vector at all — entity `health`
## only moves through core overflow or the cascade chip, so a node left at 1 HP
## moves it by exactly zero.
func test_the_hit_records_the_cascade_it_caused_live_and_shadow() -> void:
	var battle := BattleSystem.new()
	battle.graph = _graph
	battle.allocation_system = _alloc
	add_child_autofree(battle)

	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var sim_hit := DamageInstance.new()
	sim_hit.type = DamageInstance.Type.TRUE  # skip mitigation; this is about the record
	sim_hit.amount = 100000.0
	shadow._shadow_by_real[_n1].take_damage(sim_hit.amount, sim_hit)

	var live_hit := DamageInstance.new()
	live_hit.type = DamageInstance.Type.TRUE
	live_hit.amount = 100000.0
	_n1.take_damage(live_hit.amount, live_hit)

	assert_eq(live_hit.deallocations.size(), 3,
			"the killing hit records N1 plus the two nodes it islanded")
	assert_eq(sim_hit.deallocations.size(), live_hit.deallocations.size(),
			"a simulated kill records the same cascade a real one does")

	var live_ids: Array[int] = []
	for e in live_hit.deallocations:
		live_ids.append(e.node_id)
	var sim_ids: Array[int] = []
	for e in sim_hit.deallocations:
		sim_ids.append(e.node_id)
	live_ids.sort()
	sim_ids.sort()
	assert_eq(sim_ids, live_ids, "and it names the same nodes, by stable id")
	assert_false(live_ids.has(0), "every recorded entry carries a real stable id")


## The bar's numbers and the floater's number are allowed to disagree, and on an
## overkill they always do. Owner call 2026-08-21: a 3 HP node taking 5
## effective "lost 3 HP, and died" — the floater still says 5.
func test_overkill_records_the_bar_delta_and_the_floater_number_separately() -> void:
	var hp := _n2.node_board.get_stat(&"node_health") as PoolStat
	hp.set_current(3.0)
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.amount = 10.0
	_n2.take_damage(hit.amount, hit)

	assert_almost_eq(hit.hp_before, 3.0, 0.01, "the bar starts where the pool was")
	assert_almost_eq(hit.hp_after, 0.0, 0.01, "and clamps at 0, never negative")
	assert_almost_eq(hit.effective_amount, 10.0, 0.01,
			"the floater reports the full post-mitigation number, not the soak")
	assert_gt(hit.hp_max, 0.0, "the bar's maximum rides along, for a fogged client")


## Scope item 5, the wire half: the cascade a hit caused survives
## capture -> var_to_bytes -> rebuild, as ids and numbers. Without this a peer
## has to re-derive the islanded set by walking the defender's navigator —
## through nodes a fogged client may not hold at all.
func test_the_recorded_cascade_survives_the_wire() -> void:
	var battle := BattleSystem.new()
	battle.graph = _graph
	battle.allocation_system = _alloc
	add_child_autofree(battle)

	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.amount = 100000.0
	hit.target = _n1
	_n1.take_damage(hit.amount, hit)
	assert_eq(hit.deallocations.size(), 3, "precondition: the kill cascaded three nodes")

	var outcome := AttackOutcome.new()
	outcome.hits = [hit] as Array[HitInstance]
	var wire: Dictionary = AttackRecord.capture(outcome, _graph)
	# Through the real encoding, not just the dictionary — a Packed*Array that
	# does not survive var_to_bytes would pass a naive round-trip.
	var round_tripped: Dictionary = bytes_to_var(var_to_bytes(wire))
	var rebuilt := AttackRecord.rebuild(round_tripped, _graph)

	assert_eq(rebuilt.hits.size(), 1, "one hit crossed")
	var peer_hit := rebuilt.hits[0]
	assert_eq(peer_hit.deallocations.size(), 3,
			"the peer receives the cascade instead of deriving one")

	var sent: Array[int] = []
	for e in hit.deallocations:
		sent.append(e.node_id)
	var got: Array[int] = []
	for e in peer_hit.deallocations:
		got.append(e.node_id)
	sent.sort()
	got.sort()
	assert_eq(got, sent, "the same nodes, by stable id, in a stable order")

	for i in hit.deallocations.size():
		assert_eq(peer_hit.deallocations[i].wound, hit.deallocations[i].wound,
				"the wound crosses")
		assert_almost_eq(peer_hit.deallocations[i].chip, hit.deallocations[i].chip, 0.0001,
				"and the chip, at float64 — a peer's HP must land on the host's number")
		assert_not_null(peer_hit.deallocations[i].node,
				"and the id resolves back to a node on the far side")
	assert_almost_eq(peer_hit.hp_before, hit.hp_before, 0.0001, "the bar's start crosses")
	assert_almost_eq(peer_hit.hp_after, hit.hp_after, 0.0001, "the bar's end crosses")
	assert_almost_eq(peer_hit.hp_max, hit.hp_max, 0.0001,
			"and its maximum, which a fogged client cannot read off the owner's board")


## Two hits with different cascade sizes must not bleed into each other: the
## dealloc arrays are ONE flat run across every hit, sliced by a per-hit count.
## An off-by-one there gives hit 0 everything and hit 1 nothing, silently.
func test_flattened_dealloc_runs_are_sliced_back_to_the_right_hits() -> void:
	var battle := BattleSystem.new()
	battle.graph = _graph
	battle.allocation_system = _alloc
	add_child_autofree(battle)

	# A hit that kills nothing, then one that cascades three.
	var quiet := DamageInstance.new()
	quiet.type = DamageInstance.Type.TRUE
	quiet.amount = 1.0
	quiet.target = _n2
	_n2.take_damage(quiet.amount, quiet)
	assert_eq(quiet.deallocations.size(), 0, "precondition: a scratch kills nothing")

	var lethal := DamageInstance.new()
	lethal.type = DamageInstance.Type.TRUE
	lethal.amount = 100000.0
	lethal.target = _n1
	_n1.take_damage(lethal.amount, lethal)

	var outcome := AttackOutcome.new()
	outcome.hits = [quiet, lethal] as Array[HitInstance]
	var rebuilt := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph))), _graph)

	assert_eq(rebuilt.hits[0].deallocations.size(), 0,
			"the scratch must not inherit the killer's cascade")
	assert_eq(rebuilt.hits[1].deallocations.size(), lethal.deallocations.size(),
			"and the killer must keep all of its own")


## A HEAL moves a bar too. capture() encodes the HP fields for every hit, so a
## HealInstance that never filled them crosses as 0/0/0 — which reads on the far
## side as "nothing to draw" rather than as a bug. A damage-only round-trip
## cannot see that, which is why this test exists separately.
func test_a_heal_carries_its_bar_numbers_across_the_wire_too() -> void:
	var hp := _n2.node_board.get_stat(&"node_health") as PoolStat
	hp.set_current(1.0)
	var heal := HealInstance.new()
	heal.amount = 3.0
	heal.target = _n2
	_n2.heal_damage(heal.amount, heal)

	assert_almost_eq(heal.hp_before, 1.0, 0.01, "the bar starts where the pool was")
	assert_gt(heal.hp_after, heal.hp_before, "and a heal moves it up")
	assert_gt(heal.hp_max, 0.0, "with a maximum to draw it against")

	var outcome := AttackOutcome.new()
	outcome.hits = [heal] as Array[HitInstance]
	var rebuilt := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph))), _graph)
	assert_almost_eq(rebuilt.hits[0].hp_before, heal.hp_before, 0.0001, "before crosses")
	assert_almost_eq(rebuilt.hits[0].hp_after, heal.hp_after, 0.0001, "after crosses")
	assert_almost_eq(rebuilt.hits[0].hp_max, heal.hp_max, 0.0001, "max crosses")


## The presentation half of a DeallocEntry must actually REACH the peer — owner
## call 2026-08-21: "could attach whatever stat grants were revoked so the
## clients can draw them if they so want". A field computed on the host and
## dropped at the boundary would satisfy the class doc and not the ask.
func test_revoked_modifier_labels_reach_the_peer() -> void:
	var battle := BattleSystem.new()
	battle.graph = _graph
	battle.allocation_system = _alloc
	add_child_autofree(battle)

	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 3.0
	m.resource_name = "Ironbark"
	_n3.modifiers.append(m)

	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.amount = 100000.0
	hit.target = _n1
	_n1.take_damage(hit.amount, hit)

	var rebuilt_hit: HitInstance = AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(
					_outcome_of(hit), _graph))), _graph).hits[0]

	var labels: Array[String] = []
	for e in rebuilt_hit.deallocations:
		for l in e.revoked_labels:
			labels.append(l)
	assert_true(labels.has("Ironbark"),
			"the modifier N3 was granting must arrive named, for the client's toast")


func _outcome_of(hit: HitInstance) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits = [hit] as Array[HitInstance]
	return outcome
