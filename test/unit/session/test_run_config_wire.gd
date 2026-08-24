extends GutTest

## #528 — RunConfig + ParticipantRoster over the wire. "The run's shape
## crosses the wire; each peer derives its own seat": this file proves the
## first half (serialization survives a round trip, including camp identity)
## and the seam into the second half ([SeatPolicy.from_roster] already exists
## and is unit-tested on its own in test_seat_policy.gd — here we only prove
## that a DECODED roster still drives it to different results per peer).

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")


func _participant(id: int, kind: Participant.Kind, camp: Faction, peer_id: int) -> Participant:
	var p := Participant.new()
	p.id = id
	p.display_name = "P%d" % id
	p.color = Color(0.1 * id, 0.2, 0.3)
	p.camp = camp
	p.kind = kind
	p.peer_id = peer_id
	return p


func _mixed_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_1, 0))
	roster.add(_participant(2, Participant.Kind.HUMAN, _CAMP_2, 42))
	roster.add(_participant(3, Participant.Kind.AI, _CAMP_2, 0))
	return roster


## #562: [enum Participant.Kind] is absolute, so ONE payload answers both
## readers — and the relation each of them actually cares about is derived, not
## carried. The old local/remote human split made this pair impossible: whatever
## the wire said, it was wrong for one of the two machines.
func test_one_payload_reads_correctly_on_both_machines() -> void:
	var decoded := ParticipantRoster.from_dict(_mixed_roster().to_dict()).all()

	for p in decoded:
		assert_eq(p.kind, Participant.Kind.HUMAN if p.id != 3 else Participant.Kind.AI,
				"kind survives encode/decode as an absolute fact")

	# Peer 0 reads it: participant 1 is mine, 2 is theirs.
	assert_true(decoded[0].is_local(0))
	assert_false(decoded[1].is_local(0))
	# Peer 42 reads the SAME payload: the answer flips, with no re-encoding.
	assert_false(decoded[0].is_local(42))
	assert_true(decoded[1].is_local(42))


func test_participant_round_trip_preserves_every_field() -> void:
	var source := _participant(5, Participant.Kind.HUMAN, _CAMP_1, 99)
	var decoded := Participant.from_dict(source.to_dict())

	assert_eq(decoded.id, source.id)
	assert_eq(decoded.display_name, source.display_name)
	assert_eq(decoded.color, source.color)
	assert_eq(decoded.camp, source.camp, "camp identity must survive — same Resource, via its path")
	assert_eq(decoded.kind, source.kind)
	assert_eq(decoded.peer_id, source.peer_id)


func test_roster_round_trip_preserves_every_participant() -> void:
	var source := _mixed_roster()
	var decoded := ParticipantRoster.from_dict(source.to_dict())

	var source_all := source.all()
	var decoded_all := decoded.all()
	assert_eq(decoded_all.size(), source_all.size())
	for i in range(source_all.size()):
		var s: Participant = source_all[i]
		var d: Participant = decoded_all[i]
		assert_eq(d.id, s.id, "participant %d id" % i)
		assert_eq(d.kind, s.kind, "participant %d kind" % i)
		assert_eq(d.camp, s.camp, "participant %d camp" % i)
		assert_eq(d.peer_id, s.peer_id, "participant %d peer_id" % i)


## The full run's shape, including a mixed roster (two humans at different
## peer_ids + an AI, distinct camps) and the seed — #528's acceptance
## spec explicitly wants every field, including camp identity.
func test_run_config_round_trip_preserves_every_field() -> void:
	var source := RunConfig.new()
	source.mode = RunConfig.Mode.VERSUS
	source.seed = 20260822
	source.ai_opponent_count = 2
	source.participants = _mixed_roster().all()

	var decoded := RunConfig.from_dict(source.to_dict())

	assert_eq(decoded.mode, source.mode)
	assert_eq(decoded.seed, source.seed)
	assert_eq(decoded.ai_opponent_count, source.ai_opponent_count)
	assert_eq(decoded.participants.size(), source.participants.size())
	for i in range(source.participants.size()):
		assert_eq(decoded.participants[i].camp, source.participants[i].camp,
				"participant %d camp identity" % i)
		assert_eq(decoded.participants[i].peer_id, source.participants[i].peer_id,
				"participant %d peer_id" % i)


## A [VictoryCondition] built via `.new()` (the common case —
## [method RunConfig.default_condition_for] does exactly this) has no
## `resource_path` and so cannot cross by reference. It decodes to `null`,
## which resolves back to the SAME default via [method RunConfig.resolved_victory_condition]
## on every peer, since that default is a pure function of `mode`.
func test_an_unauthored_victory_condition_resolves_to_the_same_default_on_both_sides() -> void:
	var source := RunConfig.new()
	source.mode = RunConfig.Mode.COOP_HOTSEAT
	var decoded := RunConfig.from_dict(source.to_dict())

	assert_null(decoded.victory_condition)
	assert_eq(decoded.resolved_victory_condition().get_script(),
			source.resolved_victory_condition().get_script(),
			"both peers must fall back to the same condition TYPE")


## The seam into #528's other acceptance bullet: two peers holding the SAME
## decoded roster derive DIFFERENT [SeatPolicy] results depending on
## `local_peer_id`, and each seats exactly its own participant.
func test_two_peers_given_the_same_decoded_roster_derive_different_seat_policies() -> void:
	var source := _mixed_roster()
	var decoded := ParticipantRoster.from_dict(source.to_dict())

	var human1: Participant = decoded.by_id(1)  # peer_id 0 (host/local)
	var human2: Participant = decoded.by_id(2)  # peer_id 42

	var e1: Entity = autofree(Entity.new())
	e1.entity_id = 101
	var e2: Entity = autofree(Entity.new())
	e2.entity_id = 102
	var entities_by_participant := {human1.id: e1, human2.id: e2}

	var policy_for_host := SeatPolicy.from_roster(entities_by_participant, decoded, 0)
	var policy_for_peer := SeatPolicy.from_roster(entities_by_participant, decoded, 42)

	assert_eq(policy_for_host.seating, SeatPolicy.Seating.SEAT,
			"a remote human elsewhere in the roster means this machine seats, not couches")
	assert_eq(policy_for_peer.seating, SeatPolicy.Seating.SEAT)
	assert_ne(policy_for_host.seated_entity_id, policy_for_peer.seated_entity_id,
			"two different peers must seat two different entities")
	assert_eq(policy_for_host.seated_entity_id, e1.entity_id, "host seats exactly its own participant")
	assert_eq(policy_for_peer.seated_entity_id, e2.entity_id, "peer seats exactly its own participant")
