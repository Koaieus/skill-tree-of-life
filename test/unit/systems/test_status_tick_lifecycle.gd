extends GutTest

## #879 / #1256 (ADR 0040) — the lifecycle wiring around NodeCombat's status slice (#872):
## - the tick as its own step of `TurnManager.end_turn` (`Entity.resolve_turn_end`):
##   entity host then owned-node sweep, owner-filtered, before `turn_ended`;
##   never in `start_turn`, `abandon_turn` or `adopt_turn`;
## - a tick's damage gating the NEXT turn start's regen;
## - every `AllocationSystem` dealloc path clearing statuses.
## `test_node_combat_status.gd` pins apply/tick/remove/clear by hand; this
## file is the wiring that calls `tick_statuses()` for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## A StatusDef whose `_on_tick` damages the node — journals ticks so a test
## can count them, and doubles as the "poison"-shaped def the ordering test
## needs (damage -> `_damaged_since_upkeep` -> next turn's regen gate).
class SpyDef:
	extends StatusDef
	var ticks: Array = []
	var damage_per_tick: float = 0.0

	func _on_tick(node: NodeCombat, before: float, after: float) -> void:
		ticks.append([before, after])
		if damage_per_tick > 0.0:
			node.take_damage(damage_per_tick, null)


## Plain tick/remove journal — no side effects of its own. Used for the
## bystanders in the signal-level re-entrancy test below.
class TrackedDef:
	extends StatusDef
	var ticks: Array = []
	var removed: int = 0

	func _on_tick(_node: NodeCombat, before: float, after: float) -> void:
		ticks.append([before, after])

	func _on_removed(_node: NodeCombat) -> void:
		removed += 1


## The def that DOES the cascading: from inside its own `_on_tick` (itself
## mid-[method NodeCombat.tick_statuses], itself mid-sweep in [method Entity.resolve_turn_end]),
## force-deallocates a SIBLING node still queued behind it in the same sweep,
## then force-deallocates the node it is CURRENTLY ticking.
class CascadeDef:
	extends TrackedDef
	var alloc: AllocationSystem
	var also_kill: SkillNode

	func _on_tick(node: NodeCombat, before: float, after: float) -> void:
		super(node, before, after)
		if also_kill != null:
			alloc.force_deallocate(also_kill)
		alloc.force_deallocate(node.real())


var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)


func _make_entity(n: String) -> Entity:
	var e := Entity.new()
	e.name = n
	e.display_name = n
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return e


func _def(id: StringName, power_max: float, decay: float = 1.0) -> SpyDef:
	var d := SpyDef.new()
	d.id = id
	d.power_max = power_max
	d.decay = FlatDecay.new(decay)
	return d


func _new_node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	return n

## A plain journal for the ENTITY host — `_on_tick` receives an EntityCombat
## there, so the param is untyped (SpyDef's is NodeCombat-typed).
class HostSpyDef:
	extends StatusDef
	var ticks: Array = []

	func _on_tick(_host, before: float, after: float) -> void:
		ticks.append([before, after])


## Kills the entity from inside its own turn-end tick — the DoT-death shape.
class LethalDef:
	extends StatusDef
	var victim: Entity
	var ticks: int = 0

	func _on_tick(_host, _before: float, _after: float) -> void:
		ticks += 1
		victim.die()


## End the current turn and hand it to [param next] deterministically: the
## ready set is forced to exactly [param next], so `_tick_until_ready` picks it
## without running the initiative clock.
func _end_turn_to(next: Entity) -> void:
	for e in get_tree().get_nodes_in_group(Entity.READY_GROUP):
		e.remove_from_group(Entity.READY_GROUP)
	next.add_to_group(Entity.READY_GROUP)
	_tm.end_turn()


## One played-out turn of [param e], from a free cursor back to a free one —
## ended through the real `end_turn` (where the tick lives), then the handed-on
## cursor is dropped so the next call can start any entity.
func _play_turn(e: Entity) -> void:
	_tm.start_turn(e)
	_end_turn_to(e)
	_tm.adopt_turn(null, _tm.turns_taken)


# ── The moment: end_turn ticks both hosts once; start/abandon/adopt never ──

func test_both_hosts_tick_once_in_end_turn_and_never_in_start_turn() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	var b: Entity = autofree(_make_entity("B"))
	_graph.entities_container.add_child(b)
	await get_tree().process_frame

	var core := _new_node()
	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core
	_alloc.force_allocate(a, node)

	var d := _def(&"poison", 10.0, 0.0)
	d.damage_per_tick = 1.0
	node.get_combat().apply_status(d, 5.0)
	var hp0: float = node.get_current_hp()
	var h := HostSpyDef.new()
	h.id = &"rot"
	h.power_max = 10.0
	h.decay_per_tick = 0.0
	a.get_combat().apply_status(h, 5.0)

	var at_began: Array = []
	a.turn_began.connect(func() -> void: at_began.append([d.ticks.size(), h.ticks.size()]))
	var at_ended: Array = []
	_tm.turn_ended.connect(func(e: Entity) -> void:
		at_ended.append([e, d.ticks.size(), h.ticks.size(), node.get_current_hp()]))

	_tm.start_turn(a)
	assert_eq(at_began, [[0, 0]], "turn start ticks neither host")
	assert_eq(d.ticks.size(), 0, "start_turn never ticks a node status")
	assert_eq(h.ticks.size(), 0, "start_turn never ticks an entity-host status")

	_end_turn_to(b)
	assert_eq(at_ended.size(), 1, "turn_ended fires once")
	assert_eq(at_ended[0][0], a)
	assert_eq(at_ended[0][1], 1, "the node DoT ticked exactly once before turn_ended")
	assert_eq(at_ended[0][2], 1, "the entity-host status ticked exactly once before turn_ended")
	assert_lt(float(at_ended[0][3]), hp0, "and its damage has already landed")
	assert_eq(_tm.current_entity, b, "end_turn handed on")
	assert_eq(d.ticks.size(), 1, "B's turn start does not tick A's statuses")
	assert_eq(h.ticks.size(), 1)


func test_abandon_turn_never_ticks_alive_or_dying() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var d := _def(&"poison", 5.0, 0.0)
	core.get_combat().apply_status(d, 3.0)
	var h := HostSpyDef.new()
	h.id = &"rot"
	h.power_max = 5.0
	h.decay_per_tick = 0.0
	a.get_combat().apply_status(h, 3.0)

	# The status sandbox's `disarm()` shape: an alive bearer, abandoned.
	_tm.start_turn(a)
	_tm.abandon_turn(a)
	assert_eq(d.ticks.size(), 0, "an abandoned (alive) turn never ticks a node status")
	assert_eq(h.ticks.size(), 0, "an abandoned (alive) turn never ticks an entity-host status")

	# The death shape: GameRoot._pull_from_turn_loop on entity_dying.
	_tm.start_turn(a)
	var pull := func(e: Entity) -> void: _tm.abandon_turn(e)
	Events.entity_dying.connect(pull)
	a.die()
	Events.entity_dying.disconnect(pull)
	assert_null(_tm.current_entity, "the death abandoned the turn")
	assert_eq(d.ticks.size(), 0, "a turn abandoned by death never ticks")
	assert_eq(h.ticks.size(), 0)


func test_adopt_turn_never_ticks() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	var b: Entity = autofree(_make_entity("B"))
	_graph.entities_container.add_child(b)
	await get_tree().process_frame

	var node_a := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node_a)
	a.core_location = node_a

	var d := _def(&"poison", 5.0)
	node_a.get_combat().apply_status(d, 3.0)

	# A resync repair is neither a real turn begin nor a real turn end.
	_tm.adopt_turn(a, 1)
	_tm.adopt_turn(b, 2)
	_tm.adopt_turn(null, 2)
	assert_eq(d.ticks.size(), 0, "adopting onto and off a cursor must never tick a status")

	# B's played turn: A's status must not tick.
	_play_turn(b)
	assert_eq(d.ticks.size(), 0, "A's status must not tick on B's turn end")

	# A's played turn: ticks exactly once.
	_play_turn(a)
	assert_eq(d.ticks.size(), 1, "A's own played turn ticks its status exactly once")


func test_a_dot_killing_the_actor_at_its_own_turn_end_still_hands_on() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	var b: Entity = autofree(_make_entity("B"))
	_graph.entities_container.add_child(b)
	await get_tree().process_frame

	var core_a := _new_node()
	var core_b := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core_a)
	a.core_location = core_a
	_alloc.force_allocate(b, core_b)
	b.core_location = core_b

	var lethal := LethalDef.new()
	lethal.id = &"poison"
	lethal.power_max = 5.0
	lethal.victim = a
	core_a.get_combat().apply_status(lethal, 3.0)

	var ended: Array = []
	_tm.turn_ended.connect(func(e: Entity) -> void: ended.append(e))
	var pull := func(e: Entity) -> void:
		e.remove_from_group(Entity.READY_GROUP)
		_tm.abandon_turn(e)
	Events.entity_dying.connect(pull)

	_tm.start_turn(a)
	_end_turn_to(b)
	Events.entity_dying.disconnect(pull)

	assert_eq(lethal.ticks, 1, "the lethal DoT ticked once, at A's turn end")
	assert_true(a.is_dead, "A died to its own turn-end tick")
	assert_eq(ended, [a], "turn_ended fired exactly once, for A")
	assert_eq(_tm.current_entity, b, "end_turn still handed the turn to the next ready entity")


func test_a_poison_landed_before_the_first_turn_ticks_at_its_end() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var node_a := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node_a)
	a.core_location = node_a

	var d := _def(&"poison", 5.0)
	node_a.get_combat().apply_status(d, 3.0)

	_tm.start_turn(a)
	assert_eq(a.turns_taken, 1, "fixture: this is A's first turn")
	assert_eq(d.ticks.size(), 0, "not at its start")
	_end_turn_to(a)
	assert_eq(d.ticks.size(), 1, "the first turn's end ticks it")


# ── Regen gate: a tick suppresses the NEXT turn start's regen ────────────────

func test_tick_damage_suppresses_the_next_turn_starts_regen_only() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var node_a := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node_a)
	a.core_location = node_a

	# Turn 1 runs no upkeep (turns_taken == 1) — the regen under test is turn 2's.
	_tm.start_turn(a)

	# Below max HP (regen-eligible) without tripping `_damaged_since_upkeep` —
	# restore_current_hp bypasses damage/heal signals by design.
	node_a.restore_current_hp(maxf(node_a.get_max_hp() - 10.0, 0.0))

	var d := _def(&"poison", 10.0, 0.0)
	d.damage_per_tick = 1.0
	node_a.get_combat().apply_status(d, 5.0)

	# Turn 1 ends: the tick damages; turn 2's start regen must see it.
	_end_turn_to(a)
	assert_eq(d.ticks.size(), 1, "fixture: turn 1's end ticked")
	assert_eq(node_a.regen_stacks, 0,
			"the next turn start's regen is suppressed by the prior turn-end tick")

	# No tick at turn 2's end: turn 3's regen fires.
	node_a.get_combat().clear_statuses()
	_end_turn_to(a)
	assert_eq(node_a.regen_stacks, 1, "the regen after that fires")




# ── Clear on ownership loss ───────────────────────────────────────────────────

func test_force_deallocate_clears_statuses_and_stops_ticking() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d := _def(&"poison", 5.0)
	node.get_combat().apply_status(d, 3.0)
	assert_false(node.get_combat().get_statuses().is_empty())

	_alloc.force_deallocate(node)
	assert_true(node.get_combat().get_statuses().is_empty(),
			"force_deallocate must clear the node's statuses")

	_play_turn(a)
	assert_eq(d.ticks.size(), 0, "a node cleared by force_deallocate must not tick")


func test_deallocate_voluntary_clears_statuses() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d := _def(&"blind", 5.0)
	node.get_combat().apply_status(d, 2.0)

	assert_true(_alloc.deallocate(node, a), "precondition: a plain non-core dealloc must succeed")
	assert_true(node.get_combat().get_statuses().is_empty(),
			"voluntary deallocate must clear statuses")


func test_deallocate_all_owned_clears_every_owned_nodes_statuses() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d_core := _def(&"poison", 5.0)
	var d_node := _def(&"blind", 5.0)
	core.get_combat().apply_status(d_core, 2.0)
	node.get_combat().apply_status(d_node, 2.0)

	_alloc.deallocate_all_owned(a)
	assert_true(core.get_combat().get_statuses().is_empty(), "core's statuses must clear too")
	assert_true(node.get_combat().get_statuses().is_empty())

	_play_turn(a)
	assert_eq(d_core.ticks.size(), 0)
	assert_eq(d_node.ticks.size(), 0)


# ── Sweep re-entrancy (Sage review, hub amendment 2026-09-14) ────────────
#
# #872 pins the SLICE-level half (a status vanishing mid-tick_statuses).
# This is the SWEEP-level half: a tick stripping its own node — and a sibling
# still queued behind it in the owned-set snapshot — mid-sweep.

func test_force_dealloc_from_inside_a_tick_does_not_crash_and_stops_both_nodes() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var n1 := _new_node()
	var n2 := _new_node()
	var n3 := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, n1)
	a.core_location = n1
	_alloc.force_allocate(a, n2)
	_alloc.force_allocate(a, n3)

	# Mirror order n1 -> n2 -> n3: the sweep walks the owned set in that
	# order, so n2's cascade (below) fires with n3 still queued.
	var d1 := TrackedDef.new()
	d1.id = &"d1"
	d1.power_max = 5.0
	n1.get_combat().apply_status(d1, 3.0)

	var d2 := CascadeDef.new()
	d2.id = &"d2"
	d2.power_max = 5.0
	d2.alloc = _alloc
	d2.also_kill = n3
	n2.get_combat().apply_status(d2, 3.0)

	var d3 := TrackedDef.new()
	d3.id = &"d3"
	d3.power_max = 5.0
	n3.get_combat().apply_status(d3, 3.0)

	# The test completing at all (no error on a node stripped mid-sweep) is
	# itself part of the assertion.
	_play_turn(a)

	assert_eq(d1.ticks.size(), 1, "n1 (unaffected bystander) ticked exactly once")
	assert_true(n2.get_combat().get_statuses().is_empty(), "n2's own cascade cleared its status")
	assert_eq(d2.removed, 1, "n2's _on_removed fired exactly once")
	assert_true(n3.get_combat().get_statuses().is_empty(), "n3 was cleared before its own turn in the sweep")
	assert_eq(d3.ticks.size(), 0, "n3's _on_tick must never fire — cleared before it ran")

	_play_turn(a)
	assert_eq(d1.ticks.size(), 2, "n1 keeps ticking on a's next turn")
	assert_eq(d2.ticks.size(), 1, "n2 left the owned set — no further tick")
	assert_eq(d3.ticks.size(), 0, "n3 left the owned set — no further tick")


func test_a_node_that_changes_owner_ticks_at_its_new_owners_turn_end() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	var b: Entity = autofree(_make_entity("B"))
	_graph.entities_container.add_child(b)
	await get_tree().process_frame

	var core_a := _new_node()
	var core_b := _new_node()
	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core_a)
	a.core_location = core_a
	_alloc.force_allocate(b, core_b)
	b.core_location = core_b
	_alloc.force_allocate(a, node)

	var d := _def(&"poison", 5.0)
	node.get_combat().apply_status(d, 3.0)
	_alloc.force_allocate(b, node)
	assert_false(node.get_combat().get_statuses().is_empty(),
			"fixture: a direct capture keeps the status")

	_play_turn(a)
	assert_eq(d.ticks.size(), 0, "the former owner's turn end must not tick it")

	_play_turn(b)
	assert_eq(d.ticks.size(), 1, "the new owner's turn end ticks it exactly once")


func test_a_dot_kill_mid_sweep_does_not_error() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	var n1 := _new_node()
	var n2 := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core
	_alloc.force_allocate(a, n1)
	_alloc.force_allocate(a, n2)

	var killer := _def(&"poison", 0.0, 0.0)
	killer.damage_per_tick = 1.0e6
	n1.get_combat().apply_status(killer, 1.0)
	var bystander := _def(&"blind", 5.0)
	n2.get_combat().apply_status(bystander, 3.0)

	_play_turn(a)
	assert_eq(killer.ticks.size(), 1, "the lethal DoT ticked once")
	assert_eq(bystander.ticks.size(), 1, "the sweep carried on past the kill")
