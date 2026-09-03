extends GutTest

## #668 — a broadcast [LootPickOffer] must open a picker on ONE mirror peer.
##
## [method CommandLink.send_loot_offer] is an unaddressed `transport.send`, so
## the same offer arrives on every mirror. Before this gate, both clients raised
## a picker for it and whichever answered first submitted a [PickLootCommand]
## for a collector that was not theirs. Invisible at one client — "every mirror
## peer" and "the right mirror peer" are the same set — which is why it survived
## #564 and #646.
##
## The broadcast itself is not re-proved here (it is `send_loot_offer`'s two-line
## body, and `test_loot_offer_split.gd` already covers the send/receive leg);
## what this file stages is its consequence — the IDENTICAL offer landing on two
## mirror peers that seat different humans.
##
## [b]Assertions are per-instance, never on the bus.[/b] `Events` is a shared
## autoload, so two [LootSystem]s in one process emit on the same signal and an
## emission count alone cannot say WHICH peer opened. Each peer's own
## `_pending_mirror_request` is the discriminator; the bus count only backs the
## "exactly one" wording.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _PEER_A := 7
const _PEER_B := 9


func _mod(v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


## Two HUMAN seats on two different machines — the versus shape the LAN is for,
## and the smallest roster in which "every mirror peer" and "the right one"
## differ at all.
func _two_peer_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for pair: Array in [[1, _PEER_A], [2, _PEER_B]]:
		var p := Participant.new()
		p.id = pair[0]
		p.display_name = "Human_%d" % pair[0]
		p.kind = Participant.Kind.HUMAN
		p.peer_id = pair[1]
		roster.add(p)
	return roster


## One mirror peer's world: a graph holding an entity per roster seat (spawned
## in roster order, so `entity_id` minting matches across peers exactly as
## `mp_procgen_sandbox`'s client path relies on), plus the adapter chain the
## real scene wires — applier, registry, MIRROR link, [LootSystem].
##
## [param roster] is the SAME instance both peers get, which is the point: a
## roster is identical on every machine and only `local_peer_id` differs.
func _mirror(label: String, local_peer: int, roster: ParticipantRoster) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)

	var by_participant: Dictionary[int, Entity] = {}
	for p in roster.all():
		var ent: Entity = autofree(Entity.new())
		ent.display_name = "%s_p%d" % [label, p.id]
		ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
		# Normally stamped by `GameRoot.apply_roster`, which this fixture does
		# not run — without it every participant lookup misses and both peers
		# would answer "not mine" for the wrong reason.
		ent.participant_id = p.id
		graph.entities_container.add_child(ent)
		by_participant[p.id] = ent
	await get_tree().process_frame

	var applier := CommandApplier.new()
	applier.graph = graph
	add_child_autofree(applier)

	var registry := LootPickRegistry.new()
	registry.roster = roster
	registry.local_peer_id = local_peer
	add_child_autofree(registry)

	var link := CommandLink.new()
	link.command_applier = applier
	link.graph = graph
	link.mode = CommandLink.Mode.MIRROR
	add_child_autofree(link)

	var system := LootSystem.new()
	system.command_applier = applier
	system.command_link = link
	system.pick_registry = registry
	add_child_autofree(system)

	return {
		"graph": graph, "applier": applier, "registry": registry,
		"link": link, "system": system, "entities": by_participant,
	}


## The wire form a broadcast delivers, byte-identical to both peers.
func _stat_offer(collector_id: int) -> LootPickOffer:
	var offer := LootPickOffer.new()
	offer.kind = LootPickOffer.KIND_STAT
	offer.request_id = 1
	offer.collector_id = collector_id
	offer.stat_candidates = [_mod(1.0), _mod(2.0)] as Array[StatModifier]
	return offer


## Acceptance 1 + 2 + 3: exactly one of two mirror peers opens the picker, and
## it is the one that seats the collector.
func test_only_the_peer_that_seats_the_collector_opens_a_picker() -> void:
	var roster := _two_peer_roster()
	var a := await _mirror("a", _PEER_A, roster)
	var b := await _mirror("b", _PEER_B, roster)

	var raised: Array[LootPickRequest] = []
	var on_request := func(r: LootPickRequest) -> void: raised.append(r)
	Events.loot_pick_requested.connect(on_request)

	# Participant 1 sits at peer A. The offer goes to BOTH links, exactly as
	# the unaddressed broadcast delivers it.
	var offer := _stat_offer((a["entities"][1] as Entity).entity_id)
	(a["link"] as CommandLink).loot_offer_received.emit(offer)
	(b["link"] as CommandLink).loot_offer_received.emit(offer)
	await get_tree().process_frame
	Events.loot_pick_requested.disconnect(on_request)

	assert_not_null((a["system"] as LootSystem)._pending_mirror_request,
			"the peer that SEATS the collector still gets its picker, unchanged")
	assert_null((b["system"] as LootSystem)._pending_mirror_request,
			"#668 — a peer that does not seat the collector must raise nothing")
	assert_eq(raised.size(), 1,
			"exactly one request on the shared Events bus, not one per mirror peer")


## The mirror image, so the gate cannot be passing by always answering false:
## an offer for participant 2 opens on B and stays silent on A.
func test_the_gate_follows_the_collector_rather_than_favouring_one_peer() -> void:
	var roster := _two_peer_roster()
	var a := await _mirror("a", _PEER_A, roster)
	var b := await _mirror("b", _PEER_B, roster)

	var offer := _stat_offer((b["entities"][2] as Entity).entity_id)
	(a["link"] as CommandLink).loot_offer_received.emit(offer)
	(b["link"] as CommandLink).loot_offer_received.emit(offer)
	await get_tree().process_frame

	assert_null((a["system"] as LootSystem)._pending_mirror_request)
	assert_not_null((b["system"] as LootSystem)._pending_mirror_request)


## A refused offer must not disturb what this peer already has open. The gate
## returns BEFORE `_force_settle_pending_mirror_request`, which forfeits — so a
## rival's offer arriving mid-pick would otherwise close this peer's own picker
## with an empty answer.
func test_a_foreign_offer_does_not_forfeit_this_peers_own_open_request() -> void:
	var roster := _two_peer_roster()
	var a := await _mirror("a", _PEER_A, roster)

	(a["link"] as CommandLink).loot_offer_received.emit(
			_stat_offer((a["entities"][1] as Entity).entity_id))
	await get_tree().process_frame
	var mine: Variant = (a["system"] as LootSystem)._pending_mirror_request
	assert_not_null(mine, "fixture guard: this peer has a picker open")

	# The rival's offer, broadcast to everyone including this peer.
	var foreign := _stat_offer((a["entities"][2] as Entity).entity_id)
	foreign.request_id = 2
	(a["link"] as CommandLink).loot_offer_received.emit(foreign)
	await get_tree().process_frame

	assert_false(mine.is_resolved(),
			"#668 — bailing on a foreign offer must not forfeit the local picker")
	assert_eq((a["system"] as LootSystem)._pending_mirror_request, mine,
			"and must not replace it either")


## The single-machine configurations that have no roster at all (a hand-authored
## sandbox, a headless fixture) must behave exactly as they did before #668 —
## nobody is remote there, so everything is local. A gate that swallowed these
## offers would read as a picker that never opens, which is worse than the bug.
func test_a_run_with_no_roster_still_opens_its_picker() -> void:
	var roster := _two_peer_roster()
	var a := await _mirror("a", _PEER_A, roster)
	(a["registry"] as LootPickRegistry).roster = null

	(a["link"] as CommandLink).loot_offer_received.emit(
			_stat_offer((a["entities"][2] as Entity).entity_id))
	await get_tree().process_frame

	assert_not_null((a["system"] as LootSystem)._pending_mirror_request,
			"no roster is one machine — the offer cannot be for anyone else")


## The predicate's own table, unit-level, so a future edit that quietly turns it
## into `not is_remote_collector` fails here rather than only in the two-peer
## staging above. See [method LootPickRegistry.is_local_collector]'s doc.
func test_is_local_collector_is_not_the_negation_of_is_remote_collector() -> void:
	var roster := _two_peer_roster()
	var registry := LootPickRegistry.new()
	registry.roster = roster
	registry.local_peer_id = _PEER_A
	add_child_autofree(registry)

	assert_false(registry.is_local_collector(null), "a null collector is nobody's")
	assert_false(registry.is_remote_collector(null))

	var npc: Entity = autofree(Entity.new())
	assert_false(registry.is_local_collector(npc), "an NPC seats nobody, here or elsewhere")
	assert_false(registry.is_remote_collector(npc), "and both predicates say so")

	var ai_seat: Entity = autofree(Entity.new())
	ai_seat.participant_id = 2
	roster.by_id(2).kind = Participant.Kind.AI
	assert_false(registry.is_local_collector(ai_seat),
			"an AI is simulated somewhere, but no human input is awaited for it")
	assert_false(registry.is_remote_collector(ai_seat))

	var mine: Entity = autofree(Entity.new())
	mine.participant_id = 1
	assert_true(registry.is_local_collector(mine))
	assert_false(registry.is_remote_collector(mine))

	registry.local_peer_id = _PEER_B
	assert_false(registry.is_local_collector(mine))
	assert_true(registry.is_remote_collector(mine))
