extends GutTest

## #646 — split the pick-offer from the outcome record.
##
## [b]Two things this pins.[/b]
##   1. The confirm/apply ordering fix: before it, [CommandLink] broadcast a
##      [LootRoundCommand] BEFORE its round had run (the outcome was stamped
##      deep inside `_apply`), so the wire carried an empty `resolved` and a
##      receiving peer read that as an unstamped INITIATE and rolled its OWN
##      divergent pick — a real, empirically-confirmed divergence, not a
##      remote-collector special case.
##      `test_a_local_or_npc_round_still_mirrors_correctly` and
##      `test_a_single_survivor_auto_grants_and_still_mirrors` are the
##      regression guard for every loot round with no human in it, which this
##      fix touches too.
##   2. The host's queue is never held awaiting a remote human's pick (issue
##      #646 acceptance 3) — the offer/pick/roll sequence now runs OUTSIDE
##      [CommandApplier]'s queue between rounds.
##
## Harness cherry-picked near-verbatim from `wt-loot-pick-remote`
## (`9089ffc`, per the #646 dispatch note) — two [Graph]s, two
## [CommandApplier]s, a real [CommandLink] between them via
## [method LoopbackTransport.pair]. That branch's `command_applier.gd` diff
## (the rejected late-confirm exception) is NOT taken; only the harness shape
## is.
##
## [b]`_AlwaysRemoteRegistry` stands in for a still-missing piece.[/b]
## [method LootPickRegistry.is_remote_collector] cannot yet answer for real —
## nothing in the codebase correlates a live [Entity] back to the
## [Participant] that seats it (see `loot_pick_registry.gd`'s class doc). This
## harness exercises the parking/answering/closing machinery in isolation from
## that gap.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")


class _AlwaysRemoteRegistry extends LootPickRegistry:
	func is_remote_collector(_collector: Entity) -> bool:
		return true


func _mod(id: StringName, op: int, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = v
	return m


func _build_world(label: String, candidates: Array[StatModifier],
		registry: LootPickRegistry = null) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)

	var relic := _SKILL_NODE_SCENE.instantiate() as SkillNode
	relic.name = "Relic_%s" % label
	graph.skill_nodes_container.add_child(relic)

	var collector: Entity = autofree(Entity.new())
	collector.display_name = "Collector_%s" % label
	collector.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(collector)
	await get_tree().process_frame
	collector.core_location = relic

	var applier := CommandApplier.new()
	applier.graph = graph
	if registry != null:
		applier.loot_pick_registry = registry
		add_child_autofree(registry)
	add_child_autofree(applier)

	var addon := SkillDustAddon.new()
	var weights: Array[float] = []
	for _c in candidates:
		weights.append(1.0)
	addon.candidates = candidates
	addon.weights = weights
	addon.rounds = 1
	addon.command_applier = applier
	addon.pick_registry = registry
	relic.add_child(addon)

	return {
		"graph": graph, "applier": applier, "relic": relic,
		"collector": collector, "addon": addon,
	}


func _link(applier: CommandApplier, graph: Graph, transport: NetworkTransport,
		mode: CommandLink.Mode, registry: LootPickRegistry = null) -> CommandLink:
	var link := CommandLink.new()
	link.transport = transport
	link.command_applier = applier
	link.graph = graph
	link.loot_pick_registry = registry
	link.mode = mode
	add_child_autofree(link)
	return link


## Latches the addon's internal round state directly — bypassing the real
## pickup event ([method SkillDustAddon._on_carrier_owner_changed]), which
## these wire-focused tests don't need to exercise — and kicks off the SAME
## authority-side resolver `_on_carrier_owner_changed` would (#646: there is no
## "submit an empty command" door left; the offer/pick/roll sequence has to be
## started directly).
func _open_stat_round(world: Dictionary) -> void:
	var addon: SkillDustAddon = world["addon"]
	var applier: CommandApplier = world["applier"]
	addon._collector = world["collector"]
	addon._rounds_remaining = 1
	addon._phase = SkillDustAddon.Phase.STAT
	applier.notify_loot_round_opened()
	addon._run_round()


func test_a_local_or_npc_round_still_mirrors_correctly() -> void:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var host := await _build_world("host", candidates.duplicate(true))
	var client := await _build_world("client", candidates.duplicate(true))
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST)
	_link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)

	_open_stat_round(host)
	await get_tree().process_frame

	assert_eq(
		(host["collector"] as Entity).core_modifiers.size(),
		(client["collector"] as Entity).core_modifiers.size(),
		"the client must replay the same grant the host rolled, not roll its own"
	)
	assert_eq(WorldFingerprint.compute(host["graph"]), WorldFingerprint.compute(client["graph"]),
			"worlds must agree after an ordinary (non-remote) loot round crosses the wire")


## The other grant path with no human in it (#646's dispatch note): a single
## cycle-safe survivor auto-grants directly, without ever raising a
## [LootPickRequest] at all — no request means no claim, no picker, and
## nothing for a remote-vs-local distinction to even apply to.
func test_a_single_survivor_auto_grants_and_still_mirrors() -> void:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 3.0),
	]
	var host := await _build_world("host", candidates.duplicate(true))
	var client := await _build_world("client", candidates.duplicate(true))
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST)
	_link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)

	var requests := 0
	var on_request := func(_r: LootPickRequest) -> void: requests += 1
	Events.loot_pick_requested.connect(on_request)
	_open_stat_round(host)
	await get_tree().process_frame
	Events.loot_pick_requested.disconnect(on_request)

	assert_eq(requests, 0, "one survivor is no real choice — nothing is offered")
	assert_eq((host["collector"] as Entity).core_modifiers.size(), 1)
	assert_eq(
		(host["collector"] as Entity).core_modifiers.size(),
		(client["collector"] as Entity).core_modifiers.size(),
		"the client replays the auto-grant too"
	)
	assert_eq(WorldFingerprint.compute(host["graph"]), WorldFingerprint.compute(client["graph"]))


func test_a_remote_collectors_pick_round_trips_and_closes_the_clients_gate() -> void:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var host_registry := _AlwaysRemoteRegistry.new()
	var host := await _build_world("host", candidates.duplicate(true), host_registry)
	var client := await _build_world("client", candidates.duplicate(true))
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	var host_link := _link(host["applier"], host["graph"], pair[0],
			CommandLink.Mode.BROADCAST, host_registry)
	var client_link := _link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)
	var offers: Array[LootPickOffer] = []
	client_link.loot_offer_received.connect(func(o: LootPickOffer) -> void: offers.append(o))

	var collector_id: int = (host["collector"] as Entity).entity_id
	_open_stat_round(host)
	await get_tree().process_frame

	assert_eq(host_registry.pending_count(), 1,
			"the host parks a question for a remote human rather than auto-resolving it")
	assert_eq((host["applier"] as CommandApplier).pending_count(), 0,
			"issue #646 acceptance 3 — the host's queue is not held awaiting the pick")
	assert_eq(offers.size(), 1, "the downward LootPickOffer reached the peer (#646)")
	assert_eq(offers[0].collector_id, collector_id)
	assert_eq(offers[0].request_id, 1)
	assert_eq(offers[0].stat_candidates.size(), 2)

	# The client answers, standing in for its (not-yet-built, #463-adjacent) HUD
	# flow. request_id 1 is the first (and only) parked request.
	#
	# LoopbackTransport delivers synchronously and the host's own awaited pick
	# resumes synchronously off the resolved signal, so this ONE `submit` call
	# runs the whole remaining round trip to completion before it returns — the
	# "awaiting" window opens and closes within this call, rather than
	# surviving to be observed here. A real link (ENet, #463) would leave it
	# observably open for the round trip; what matters is that it does not get
	# stuck open, checked below.
	var pick := PickLootCommand.new(collector_id, 1, 0)
	(client["applier"] as CommandApplier).submit(pick)
	await get_tree().process_frame

	assert_eq(host_registry.pending_count(), 0,
			"the answer lands on the parked request rather than being dropped")
	assert_false((client["applier"] as CommandApplier).is_awaiting_confirmation,
			"the round closing must close the gate — a stuck-true gate is the hang #564 exists to prevent")
	assert_eq(
		(host["collector"] as Entity).core_modifiers.size(),
		(client["collector"] as Entity).core_modifiers.size(),
		"both peers must land on the same result"
	)
	assert_eq(WorldFingerprint.compute(host["graph"]), WorldFingerprint.compute(client["graph"]),
			"worlds must agree after a client-answered loot round")


func test_a_mirror_peers_registry_stays_inert_through_a_loot_round() -> void:
	# Acceptance 4 of #522/#564: a mirror peer's LootPickRegistry.pending_count()
	# is 0 at every point of a loot round, asserted rather than left implicit —
	# the peer's addon only ever replays, so nothing is ever parked there.
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var client_registry := _AlwaysRemoteRegistry.new()
	var host := await _build_world("host", candidates.duplicate(true))
	var client := await _build_world("client", candidates.duplicate(true), client_registry)
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST)
	_link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)

	assert_eq(client_registry.pending_count(), 0)

	_open_stat_round(host)
	await get_tree().process_frame

	assert_eq(client_registry.pending_count(), 0,
			"a mirror peer never parks — it only replays what the host already resolved")


## The gate itself (#646's pick-gate owner decision): while a relic's claim
## chain is outstanding, `can_player_act` reads false even though the queue —
## unlike the pre-#646 shape — is sitting empty between rounds.
func test_has_outstanding_loot_gates_can_player_act_between_rounds() -> void:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var host_registry := _AlwaysRemoteRegistry.new()
	var host := await _build_world("host", candidates, host_registry)
	var applier: CommandApplier = host["applier"]
	var tm := TurnManager.new()
	autofree(tm)
	add_child(tm)
	tm.start_turn(host["collector"])
	var input_ctl := PlayerInputController.new()
	input_ctl.graph = host["graph"]
	input_ctl.command_applier = applier
	input_ctl.turn_manager = tm
	input_ctl.player = host["collector"]
	add_child_autofree(input_ctl)

	assert_true(input_ctl.can_player_act(), "fixture guard: nothing outstanding yet")

	_open_stat_round(host)
	await get_tree().process_frame

	assert_eq(applier.pending_count(), 0, "the queue itself is free (acceptance 3)")
	assert_true(applier.has_outstanding_loot(),
			"but the chain is still mid-pick, so End Turn must stay greyed out")
	assert_false(input_ctl.can_player_act(),
			"the explicit gate, not is_applying, is what closes it now")

	assert_true(host_registry.resolve_pick(1, 0), "answer the parked pick to let the chain finish")
	await get_tree().process_frame

	assert_false(applier.has_outstanding_loot(), "the chain reached its terminal round")
	assert_true(input_ctl.can_player_act(), "and the gate reopens")
