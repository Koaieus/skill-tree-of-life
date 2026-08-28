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
	source.participants = _mixed_roster().all()

	var decoded := RunConfig.from_dict(source.to_dict())

	assert_eq(decoded.mode, source.mode)
	assert_eq(decoded.seed, source.seed)
	assert_eq(decoded.participants.size(), source.participants.size())
	for i in range(source.participants.size()):
		assert_eq(decoded.participants[i].camp, source.participants[i].camp,
				"participant %d camp identity" % i)
		assert_eq(decoded.participants[i].peer_id, source.participants[i].peer_id,
				"participant %d peer_id" % i)


## #641 acceptance 3/6 — `scenario` replaces `level_scene` on the wire, and
## crosses as a resource PATH exactly the way `level_scene` and
## `victory_condition` already did (#528). Acceptance 6: the field genuinely
## MOVED — `scenario` is present and `level_scene` is gone, not merely
## duplicated.
func test_scenario_survives_round_trip_as_a_path_and_level_scene_is_gone() -> void:
	var source := RunConfig.new()
	source.scenario = load("res://session/scenarios/coop_versus.tres") as Scenario

	var dict := source.to_dict()
	assert_true(dict.has("scenario"), "the field genuinely moved onto the wire")
	assert_false(dict.has("level_scene"), "level_scene must not still be sent")
	assert_eq(dict["scenario"], source.scenario.resource_path,
			"scenario crosses as a PATH, not embedded content")

	var decoded := RunConfig.from_dict(dict)
	assert_eq(decoded.scenario, source.scenario,
			"a resource path resolves back to the SAME cached Resource")


## An unset [member RunConfig.scenario] must not silently degrade into a
## PATH string that decodes to something else — the same silent-null shape
## #597 names for `preset`.
func test_an_unset_scenario_round_trips_as_null() -> void:
	var source := RunConfig.new()
	var decoded := RunConfig.from_dict(source.to_dict())
	assert_null(decoded.scenario)


## #641 acceptance 3's other half — a peer generating from the DECODED config
## produces the SAME map as the host, because the decoded [Scenario] resolves
## back to the identical cached `.tres`-backed [GraphProcgenConfig], never a
## value that crossed the wire and diverged.
func test_a_client_generating_from_the_decoded_scenario_matches_the_host() -> void:
	var source := RunConfig.new()
	source.scenario = load("res://session/scenarios/coop_versus.tres") as Scenario
	source.seed = 20260827

	var decoded := RunConfig.from_dict(source.to_dict())

	var host_nodes := await _generate_from_preset(source.scenario.preset, source.seed)
	var client_nodes := await _generate_from_preset(decoded.scenario.preset, decoded.seed)

	assert_eq(client_nodes.size(), host_nodes.size(), "same seed, same node count")
	for i in host_nodes.size():
		assert_eq((client_nodes[i] as Node2D).position, (host_nodes[i] as Node2D).position,
				"node %d position must match — same seed, same preset" % i)


## Small, self-contained generation for the round-trip comparison above — a
## fresh duplicate per call, same reason `test_coop_versus_preset.gd`'s
## `_fresh_config` re-duplicates: `generate` mutates the config in place and
## `load` is cached, so two calls sharing one object would generate the SAME
## map trivially rather than proving the decoded config can reproduce it.
func _generate_from_preset(preset: GraphProcgenConfig, seed_value: int) -> Array:
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	# #349 acceptance 4: topology is a top-level module `.tres` (ExtResource);
	# duplicate(true) does not cross that boundary.
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 40
	cfg.seed = seed_value
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("nodes", [])


## Since #638 the victory condition does not cross at all — it hangs off the
## [Scenario], which crosses as a path, so a peer that decoded the same scenario
## resolves the same condition by construction. A run carrying NO scenario still
## has to end somehow, and both sides must land on the SAME fallback type.
func test_an_unauthored_victory_condition_resolves_to_the_same_default_on_both_sides() -> void:
	var source := RunConfig.new()
	source.mode = RunConfig.Mode.COOP_HOTSEAT
	var decoded := RunConfig.from_dict(source.to_dict())

	assert_false(source.to_dict().has("victory_condition"),
			"#638: the condition is the Scenario's, so it no longer crosses on RunConfig")
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
