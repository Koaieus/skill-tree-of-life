extends GutTest

## CombatWorld + `land_on(NodeCombat, CombatWorld)` (#498 step 3 — see
## docs/domain/attack-timeline.md). The acceptance this file exists for is the
## one the issue states: an outcome resolved against a shadow produces the same
## numbers the real applier would, without mutating the real world.
##
## Fixture, two factions on one graph:
##   attacker core A0
##   defender core D0 - D1 - D2, D1 - D3
## D1 is a cut vertex, so killing it islands {D2, D3} off the defender's core —
## the same shape test_entity_combat_slice.gd uses, because the point here is
## that a whole CASCADE runs on the shadow, not just a subtraction.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _attacker: Entity
var _defender: Entity
var _a0: SkillNode
var _d0: SkillNode
var _d1: SkillNode
var _d2: SkillNode
var _d3: SkillNode
var _events_fired: int = 0
var _worlds: Array[CombatWorld] = []



func before_each() -> void:
	_events_fired = 0
	_worlds = []

	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_a0 = _new_node("A0")
	_d0 = _new_node("D0")
	_d1 = _new_node("D1")
	_d2 = _new_node("D2")
	_d3 = _new_node("D3")
	_add_edge(_a0, _d0)
	_add_edge(_d0, _d1)
	_add_edge(_d1, _d2)
	_add_edge(_d1, _d3)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	# The live forced-dealloc cascade still ENTERS through the bus
	# (Events.skill_node_depleted -> BattleSystem._on_node_depleted), so without
	# one of these the live half of every comparison below would silently not
	# cascade at all and the shadow would look wrong for being right.
	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_attacker = _new_entity("Attacker")
	# Distinct factions — both entities default to `npc.tres`, which makes them
	# ALLIED, and a landing gate that asks for HOSTILE would veto every hit.
	_attacker.faction = _PLAYER_FACTION
	_defender = _new_entity("Defender")
	await get_tree().process_frame  # entity._ready: navigator wiring

	_alloc.force_allocate(_attacker, _a0)
	_attacker.core_location = _a0
	for n in [_d0, _d1, _d2, _d3]:
		_alloc.force_allocate(_defender, n)
	_defender.core_location = _d0

	for sig in _bus():
		sig.connect(_count_event)


func after_each() -> void:
	for sig in _bus():
		if sig.is_connected(_count_event):
			sig.disconnect(_count_event)
	for w in _worlds:
		w.free_shadow()


# ── fixture helpers ──────────────────────────────────────────────────────────

func _bus() -> Array[Signal]:
	var out: Array[Signal] = [
		Events.skill_node_damaged, Events.skill_node_healed, Events.skill_node_depleted,
		Events.entity_dying, Events.entity_died, Events.entity_death_shown,
	]
	return out


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


func _new_entity(n: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = n
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func _shadow() -> CombatWorld:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	return w


## One damage hit, built fresh each time so the shadow run and the live run get
## structurally identical (never shared) instances to fill in.
func _hit(target: SkillNode, amount: float, at: float) -> DamageInstance:
	var d := DamageInstance.new()
	d.type = DamageInstance.Type.TRUE  # skip mitigation: this file is about WHERE it lands
	d.target = target
	d.attacker = _attacker
	d.amount = amount
	d.arrival_time = at
	return d


## A two-wave volley on D1 big enough to kill it — wave 1 softens, wave 2 kills,
## so the cascade happens BETWEEN two landings of the same outcome.
func _killing_outcome() -> AttackOutcome:
	var hp := _d1.get_max_hp()
	var o := AttackOutcome.new()
	o.hits.append(_hit(_d1, hp * 0.5, 0.0))
	o.hits.append(_hit(_d1, hp, 1.0))
	o.hits.append(_hit(_d2, 1.0, 2.0))
	return o


func _hp_of_all() -> Dictionary:
	var out: Dictionary = {}
	for n in [_a0, _d0, _d1, _d2, _d3]:
		out[n.name] = n.get_current_hp()
	return out


func _owners_of_all() -> Dictionary:
	var out: Dictionary = {}
	for n in [_a0, _d0, _d1, _d2, _d3]:
		out[n.name] = n.owned_by
	return out


func _readout(o: AttackOutcome) -> Array:
	var rows: Array = []
	for h in OutcomeApplier.in_arrival_order(o.hits):
		var dealloc_names := PackedStringArray()
		for entry in h.deallocations:
			dealloc_names.append(entry.node.name if entry.node != null else "<null>")
		dealloc_names.sort()
		rows.append([h.target.name, h.effective_amount, h.hp_before, h.hp_after,
				h.hp_max, h.gated, dealloc_names])
	return rows


# ── the world lookup itself ──────────────────────────────────────────────────

func test_live_world_hands_back_the_node_s_own_composed_slice() -> void:
	assert_same(CombatWorld.live().combat_for(_d1), _d1.get_combat(),
			"a live world adds no state — it IS the object's own slice")
	assert_false(CombatWorld.live().is_shadow())


func test_shadow_world_hands_back_a_detached_slice_with_no_host() -> void:
	var slice := _shadow().combat_for(_d1)
	assert_not_same(slice, _d1.get_combat())
	assert_null(slice.host, "the host-null invariant: a shadow can never notify")
	assert_same(slice.real(), _d1, "but it still knows which node it stands for")
	assert_almost_eq(slice.get_current_hp(), _d1.get_current_hp(), 0.001)


func test_shadow_world_is_stable_per_node() -> void:
	var w := _shadow()
	assert_same(w.combat_for(_d1), w.combat_for(_d1),
			"asking twice must not mint a second slice — the first one holds the damage")


func test_shadow_of_one_node_snapshots_its_owner_s_whole_subgraph() -> void:
	# #498: "do not reach-bound the owned subgraph" — a node fifty hops from the
	# impact can still be in the cascade, so asking about D1 must bring D3 too.
	var w := _shadow()
	w.combat_for(_d1)
	assert_eq(w.combat_for_entity(_defender).owned().size(), 4,
			"the defender's whole territory, not just the node asked about")
	assert_not_null(w._nodes.get(_d3), "including the far side of the cut vertex")


func test_shadow_grows_across_entities_on_demand() -> void:
	var w := _shadow()
	w.combat_for(_d1)
	assert_eq(w._entities.size(), 1, "only the entity actually touched is paid for")
	w.combat_for(_a0)
	assert_eq(w._entities.size(), 2, "a second faction snapshots on first touch")
	assert_not_same(w.combat_for(_a0).owner(), w.combat_for(_d1).owner())


func test_shadow_mints_an_ownerless_slice_for_an_unallocated_conduit() -> void:
	var conduit := _new_node("Conduit")
	_add_edge(_d3, conduit)
	var slice := _shadow().combat_for(conduit)
	assert_not_null(slice, "a spell conduit has no entity to snapshot but still has a board")
	assert_null(slice.owner())
	assert_false(slice.is_allocated())


func test_ownership_bit_reads_the_same_through_a_shadow() -> void:
	var w := _shadow()
	assert_eq(w.combat_for(_d1).ownership_bit(_attacker), SkillNode.Ownership.HOSTILE)
	assert_eq(w.combat_for(_a0).ownership_bit(_attacker), SkillNode.Ownership.MINE)
	assert_eq(_d1.ownership_bit(_attacker), SkillNode.Ownership.HOSTILE,
			"and the live node still answers it the same, through the same code")


# ── the acceptance: same numbers, no mutation ────────────────────────────────

func test_applying_a_whole_outcome_to_a_shadow_leaves_the_real_world_untouched() -> void:
	var hp_before := _hp_of_all()
	var owners_before := _owners_of_all()

	OutcomeApplier.apply(_killing_outcome(), null, _shadow())

	assert_eq(_hp_of_all(), hp_before, "no real node lost HP to a simulated volley")
	assert_eq(_owners_of_all(), owners_before, "and the cascade deallocated nothing real")
	assert_eq(_events_fired, 0, "a simulated kill announces nothing on the bus")


func test_a_shadow_run_reports_the_same_numbers_the_live_run_produces() -> void:
	# The issue's acceptance, stated as a comparison rather than as fixed
	# constants: whatever the real applier does to this fixture, the shadow must
	# report identically — including each landing's HP window and the whole
	# forced-dealloc cascade the middle hit sets off.
	var simulated := _killing_outcome()
	OutcomeApplier.apply(simulated, null, _shadow())

	var real := _killing_outcome()
	OutcomeApplier.apply(real)

	assert_eq(_readout(simulated), _readout(real),
			"preview and execution are one code path; only the world differs")


func test_the_cascade_a_shadow_charges_is_the_cascade_the_live_run_charges() -> void:
	# Guards the specific thing #518 made shared: the islanded SET, and the SP
	# wound / dealloc chip each stripped node costs.
	var simulated := _killing_outcome()
	var w := _shadow()
	OutcomeApplier.apply(simulated, null, w)
	var shadow_sp: float = (w.combat_for_entity(_defender).board()
			.get_stat(&"skill_points") as PoolStat).current
	var shadow_hp: float = (w.combat_for_entity(_defender).board()
			.get_stat(&"health") as PoolStat).current

	OutcomeApplier.apply(_killing_outcome())
	var live_sp: float = (_defender.stat_board.get_stat(&"skill_points") as PoolStat).current
	var live_hp: float = (_defender.stat_board.get_stat(&"health") as PoolStat).current

	assert_almost_eq(shadow_sp, live_sp, 0.001, "same SP wound")
	assert_almost_eq(shadow_hp, live_hp, 0.001, "same dealloc_damage chip")


func test_a_shadow_cascade_islands_the_far_side_without_touching_real_ownership() -> void:
	var w := _shadow()
	OutcomeApplier.apply(_killing_outcome(), null, w)

	var defender_shadow := w.combat_for_entity(_defender)
	var still_owned := PackedStringArray()
	for n in defender_shadow.owned():
		still_owned.append(n.real().name)
	still_owned.sort()
	assert_eq(still_owned, PackedStringArray(["D0"]),
			"killing the cut vertex islands D2 and D3 off the core, on the shadow")
	assert_same(_d2.owned_by, _defender, "and the real D2 never noticed")
	assert_same(_d3.owned_by, _defender)


func test_the_third_hit_lands_on_a_node_the_shadow_cascade_already_freed() -> void:
	# The reason a slice is needed at all: hit 3 targets D2, which hit 2's
	# cascade islanded. On the shadow the target is unallocated by then, exactly
	# as it is live — an ungated resolve would still be charging it damage.
	var simulated := _killing_outcome()
	OutcomeApplier.apply(simulated, null, _shadow())
	var third: HitInstance = OutcomeApplier.in_arrival_order(simulated.hits)[2]
	assert_eq(third.target, _d2)
	assert_almost_eq(third.effective_amount, 0.0, 0.001,
			"NodeCombat.take_damage no-ops on an unowned node — same as live")
