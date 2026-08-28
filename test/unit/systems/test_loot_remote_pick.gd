extends GutTest

## #564 — the post-#646 remainder: [signal CommandLink.loot_offer_received]
## gets its first production consumer. A mirror peer translates the incoming
## [LootPickOffer] back into the SAME `Events.loot_pick_requested` /
## `Events.spell_loot_requested` emission the host path already uses, so the
## client's picker opens, its pick travels up, and the round closes.
##
## Harness lifted from `test_loot_offer_split.gd`'s two-world shape (`_build_world`
## / `_link` / `_open_stat_round`, near-verbatim) — this file adds the
## [LootSystem]-backed mirror-side adapter on top of it, and a stand-in
## "picker" (a raw `request.resolve()` call — the same thing
## `LootPicker._on_confirmed` / `SpellLootPicker._on_confirmed` do) so
## `Events.loot_pick_requested` drives the whole answer path for real, rather
## than hand-building a [PickLootCommand] directly the way the #646 tests do.

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


## #564: wire a bare [LootSystem] purely as the mirror-side adapter — no
## `turn_manager` / `battle_system` needed for this unit, both stay null (a
## documented supported configuration; see the class doc).
func _mirror_adapter(applier: CommandApplier, link: CommandLink) -> LootSystem:
	var system := LootSystem.new()
	system.command_applier = applier
	system.command_link = link
	add_child_autofree(system)
	return system


## Latches the addon's internal round state directly — bypassing the real
## pickup event — and kicks off the same authority-side resolver a real pickup
## would. See `test_loot_offer_split.gd`'s copy of this helper.
func _open_stat_round(world: Dictionary) -> void:
	var addon: SkillDustAddon = world["addon"]
	var applier: CommandApplier = world["applier"]
	addon._collector = world["collector"]
	addon._rounds_remaining = 1
	addon._phase = SkillDustAddon.Phase.STAT
	applier.notify_loot_round_opened()
	addon._run_round()


## Acceptance 1 + 4: the two-world end-to-end. The host parks for a remote
## collector, the offer crosses down, the adapter rebuilds it into the SAME
## `Events.loot_pick_requested` the host's own [HudRoot] listens for, a
## stand-in picker answers it, the pick travels up as a [PickLootCommand], the
## host's PARKED request resolves (not an already-auto-resolved one), the
## outcome comes down, and both peers land on the same result — all while the
## mirror's own [LootPickRegistry] never parks anything.
func test_a_remote_collectors_offer_opens_a_picker_and_the_pick_closes_the_round() -> void:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0),
	]
	var host_registry := _AlwaysRemoteRegistry.new()
	var client_registry := LootPickRegistry.new()
	var host := await _build_world("host", candidates.duplicate(true), host_registry)
	var client := await _build_world("client", candidates.duplicate(true), client_registry)
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST, host_registry)
	var client_link := _link(client["applier"], client["graph"], pair[1],
			CommandLink.Mode.MIRROR, client_registry)
	_mirror_adapter(client["applier"], client_link)

	# Events is a shared autoload across both worlds in this harness — the
	# HOST's own SkillDustAddon._run_stat_round ALSO emits unconditionally
	# (that is how a real HudRoot's `collector != _player` filter works), so
	# filter to the collector this test cares about rather than assuming
	# there is only one emission.
	var requests: Array[LootPickRequest] = []
	var on_request := func(r: LootPickRequest) -> void:
		if r.collector == client["collector"]:
			requests.append(r)
	Events.loot_pick_requested.connect(on_request)
	_open_stat_round(host)
	await get_tree().process_frame
	Events.loot_pick_requested.disconnect(on_request)

	assert_eq(requests.size(), 1,
			"the adapter must translate the offer into the SAME Events.loot_pick_requested the host uses")
	assert_eq(requests[0].candidates.size(), 2)
	assert_eq(client_registry.pending_count(), 0,
			"a mirror peer's registry stays inert — the adapter must not park the rebuilt request")

	# Stand in for LootPicker._on_confirmed: resolve with the chosen candidate.
	requests[0].resolve([requests[0].candidates[0]] as Array[StatModifier])
	await get_tree().process_frame

	assert_eq(host_registry.pending_count(), 0,
			"the pick landed on the host's PARKED request rather than being dropped")
	assert_eq(client_registry.pending_count(), 0,
			"still inert after the round closes")
	assert_eq(
		(host["collector"] as Entity).core_modifiers.size(),
		(client["collector"] as Entity).core_modifiers.size(),
		"both peers must land on the same result"
	)
	assert_eq(WorldFingerprint.compute(host["graph"]), WorldFingerprint.compute(client["graph"]),
			"worlds must agree after the client's own picker answers a remote pick")


## Acceptance 2: no hang with no local answer. Stands in for the host's real
## 60s timeout by resolving the parked request with a forfeit directly — what
## matters here is what happens on the CLIENT side once that outcome crosses:
## the request this peer already raised (and never answered) must not be left
## stuck open, or its picker modal would never dismiss.
func test_a_forfeited_round_closes_the_clients_open_request_without_a_local_answer() -> void:
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
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST, host_registry)
	var client_link := _link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)
	_mirror_adapter(client["applier"], client_link)

	# See the previous test for why this filters to the client's collector —
	# the host's own SkillDustAddon emits on the same shared Events bus too.
	var requests: Array[LootPickRequest] = []
	var on_request := func(r: LootPickRequest) -> void:
		if r.collector == client["collector"]:
			requests.append(r)
	Events.loot_pick_requested.connect(on_request)
	_open_stat_round(host)
	await get_tree().process_frame
	Events.loot_pick_requested.disconnect(on_request)

	assert_eq(requests.size(), 1)
	assert_false(requests[0].is_resolved(), "fixture guard: the client has not answered yet")

	assert_true(host_registry.resolve_pick(1, -1), "stand-in for the host's own timeout forfeit")
	await get_tree().process_frame

	assert_true(requests[0].is_resolved(),
			"#564 — a host-side forfeit must close the client's outstanding request, not leave it stuck open")
	assert_eq(
		(host["collector"] as Entity).core_modifiers.size(),
		(client["collector"] as Entity).core_modifiers.size(),
	)
	assert_eq(WorldFingerprint.compute(host["graph"]), WorldFingerprint.compute(client["graph"]),
			"worlds must agree after a forfeited round with no local answer")


## Acceptance 3: a client-side forfeit travels. The collector dies while the
## client's picker is up (this peer's own world, not the host's) — the same
## death guard [SkillDustAddon._await_pick] uses on the host side, mirrored for
## the rebuilt request. `chosen_index == -1` must cross the wire and land on
## the host's PARKED request, not be dropped.
func test_a_collector_death_mid_pick_forfeits_and_travels_upward() -> void:
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
	_link(host["applier"], host["graph"], pair[0], CommandLink.Mode.BROADCAST, host_registry)
	var client_link := _link(client["applier"], client["graph"], pair[1], CommandLink.Mode.MIRROR)
	_mirror_adapter(client["applier"], client_link)

	_open_stat_round(host)
	await get_tree().process_frame
	assert_eq(host_registry.pending_count(), 1, "fixture guard: the host is waiting on the remote pick")

	(client["collector"] as Entity).died.emit()
	await get_tree().process_frame

	assert_eq(host_registry.pending_count(), 0,
			"the client's death-mid-pick forfeit must land on the parked request rather than being dropped")
	assert_eq((host["collector"] as Entity).core_modifiers.size(), 0,
			"a forfeited round grants nothing")


## The spell half of the offer (#204's terminal round). Isolated from the
## multi-round [SkillDustAddon] chain — this only pins the adapter's own
## translation: spell candidates resolve through [SpellCatalog], by id, the
## same way [method LootRoundCommand.granted_spell] does (the brief's landmine
## note), not by reconstructing a [SpellDef].
func test_a_spell_offer_rebuilds_through_spellcatalog() -> void:
	var client := await _build_world("client", [])
	var system := LootSystem.new()
	system.command_applier = client["applier"]
	add_child_autofree(system)

	var offer := LootPickOffer.new()
	offer.kind = LootPickOffer.KIND_SPELL
	offer.request_id = 7
	offer.collector_id = (client["collector"] as Entity).entity_id
	offer.spell_ids = [SpellCatalog.SPARK.id]

	var requests: Array[SpellLootRequest] = []
	var on_request := func(r: SpellLootRequest) -> void: requests.append(r)
	Events.spell_loot_requested.connect(on_request)
	system._on_loot_offer_received(offer)
	Events.spell_loot_requested.disconnect(on_request)

	assert_eq(requests.size(), 1)
	assert_eq(requests[0].collector, client["collector"])
	assert_eq(requests[0].candidates.size(), 1)
	assert_eq(requests[0].candidates[0], SpellCatalog.SPARK,
			"spell candidates rebuild through SpellCatalog, the same way LootRoundCommand.granted_spell does")
