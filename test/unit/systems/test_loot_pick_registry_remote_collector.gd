extends GutTest

## #564 — `LootPickRegistry.is_remote_collector` answers from the roster
## ([member LootPickRegistry.roster] / [member LootPickRegistry.local_peer_id],
## injected the way [GameRoot] injects them at `_ready`) via
## [member Entity.participant_id], never [SeatPolicy]. See
## `.claude/rules/multiplayer-sync.md` and `systems/loot_pick_registry.gd`'s
## class doc for why a per-machine object cannot answer for a peer.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")

const _LOCAL_PEER := 1
const _REMOTE_PEER := 2


func _participant(id: int, kind: Participant.Kind, peer_id: int) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = _CAMP_1
	p.peer_id = peer_id
	return p


func _registry(roster: ParticipantRoster, local_peer_id: int) -> LootPickRegistry:
	var reg: LootPickRegistry = autofree(LootPickRegistry.new())
	reg.roster = roster
	reg.local_peer_id = local_peer_id
	return reg


func test_a_collector_seated_by_a_remote_human_is_remote() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _REMOTE_PEER))
	var collector: Entity = autofree(Entity.new())
	collector.participant_id = 1

	var reg := _registry(roster, _LOCAL_PEER)

	assert_true(reg.is_remote_collector(collector))


func test_a_collector_seated_by_the_local_human_is_not_remote() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _LOCAL_PEER))
	var collector: Entity = autofree(Entity.new())
	collector.participant_id = 1

	var reg := _registry(roster, _LOCAL_PEER)

	assert_false(reg.is_remote_collector(collector))


func test_an_npc_nobody_seats_is_not_remote() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _REMOTE_PEER))
	var npc: Entity = autofree(Entity.new())
	# participant_id left at its default (0) — nothing seats this entity.
	assert_eq(npc.participant_id, 0)

	var reg := _registry(roster, _LOCAL_PEER)

	assert_false(reg.is_remote_collector(npc))


func test_an_ai_seated_entity_is_not_remote_even_across_peers() -> void:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.AI, _REMOTE_PEER))
	var collector: Entity = autofree(Entity.new())
	collector.participant_id = 1

	var reg := _registry(roster, _LOCAL_PEER)

	assert_false(reg.is_remote_collector(collector))


func test_no_roster_means_nobody_is_remote() -> void:
	# GameSession.roster is null outside an active run (a hand-authored
	# sandbox with no lobby) — GameRoot injects that null as-is.
	var collector: Entity = autofree(Entity.new())
	collector.participant_id = 1

	var reg := _registry(null, _LOCAL_PEER)

	assert_false(reg.is_remote_collector(collector))


func test_is_remote_collector_never_reads_seat_policy() -> void:
	# Deliberate, not incidental (#564) — SeatPolicy is the per-machine half
	# of a run's setup and cannot answer for a peer, so it must never even be
	# a reachable dependency here. Assert the property surface directly
	# (rather than a source-text scan, which would also flag the class doc's
	# own explanation of why not) — no `seat_policy` field to read.
	var reg: LootPickRegistry = autofree(LootPickRegistry.new())
	for prop in reg.get_property_list():
		assert_ne(String(prop.get("name", "")).to_lower(), "seat_policy",
				"LootPickRegistry must not expose a SeatPolicy dependency — see the class doc")
