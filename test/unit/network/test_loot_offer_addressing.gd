extends GutTest

## #1176 — a parked loot pick's [LootPickOffer] is ADDRESSED to the peer that
## seats the collector's human ([method LootPickRegistry.peer_for]), never
## broadcast: "if 1 player is looting, nobody else needs to know about it until
## they select". Staged at the transport, so a regression to an unaddressed
## `send` shows up as a message on the bystander's end.

const _PEER_COLLECTOR := 2
const _PEER_BYSTANDER := 3


## Two humans on two client machines — the smallest roster in which "the
## collector's peer" and "every peer" differ.
func _roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for pair: Array in [[1, _PEER_COLLECTOR], [2, _PEER_BYSTANDER]]:
		var p := Participant.new()
		p.id = pair[0]
		p.display_name = "Human_%d" % pair[0]
		p.kind = Participant.Kind.HUMAN
		p.peer_id = pair[1]
		roster.add(p)
	return roster


func _loot_offers_on(transport: LoopbackTransport) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	transport.message_received.connect(func(payload: Dictionary) -> void:
		if payload.get(CommandLink.KEY_KIND) == CommandLink.KIND_LOOT_OFFER:
			got.append(payload))
	return got


func _collector(participant_id: int) -> Entity:
	var ent: Entity = autofree(Entity.new())
	ent.participant_id = participant_id
	return ent


func test_offer_reaches_the_collectors_peer_only() -> void:
	var ends := LoopbackTransport.pair()
	var host_end: LoopbackTransport = ends[0]
	var collector_end: LoopbackTransport = ends[1]
	var bystander_end := LoopbackTransport.attach(host_end, _PEER_BYSTANDER)
	for t: LoopbackTransport in [host_end, collector_end, bystander_end]:
		add_child_autofree(t)
	assert_eq(collector_end.my_peer_id, _PEER_COLLECTOR, "fixture guard: pair()'s client id")

	var registry := LootPickRegistry.new()
	registry.roster = _roster()
	registry.local_peer_id = host_end.my_peer_id
	add_child_autofree(registry)

	var link := CommandLink.new()
	link.transport = host_end
	link.loot_pick_registry = registry
	link.role = NetworkConfig.Role.HOST
	add_child_autofree(link)

	var at_collector := _loot_offers_on(collector_end)
	var at_bystander := _loot_offers_on(bystander_end)

	var candidates: Array[StatModifier] = [StatModifier.new()]
	var request := LootPickRequest.new(_collector(1), candidates, func(_c: Array) -> void: pass)
	registry.offer_parked.emit(request)

	assert_eq(at_collector.size(), 1, "the collector's peer gets the offer")
	assert_eq(at_bystander.size(), 0, "a third peer hears nothing until the pick lands")


func test_offer_for_the_other_human_follows_them() -> void:
	var ends := LoopbackTransport.pair()
	var host_end: LoopbackTransport = ends[0]
	var bystander_end := LoopbackTransport.attach(host_end, _PEER_BYSTANDER)
	for t: LoopbackTransport in [host_end, ends[1], bystander_end]:
		add_child_autofree(t)

	var registry := LootPickRegistry.new()
	registry.roster = _roster()
	registry.local_peer_id = host_end.my_peer_id
	add_child_autofree(registry)
	var link := CommandLink.new()
	link.transport = host_end
	link.loot_pick_registry = registry
	link.role = NetworkConfig.Role.HOST
	add_child_autofree(link)

	var at_pair_client := _loot_offers_on(ends[1])
	var at_attached := _loot_offers_on(bystander_end)

	var candidates: Array[StatModifier] = [StatModifier.new()]
	registry.offer_parked.emit(
			LootPickRequest.new(_collector(2), candidates, func(_c: Array) -> void: pass))

	assert_eq(at_pair_client.size(), 0)
	assert_eq(at_attached.size(), 1, "addressing follows the roster, not the first client")
