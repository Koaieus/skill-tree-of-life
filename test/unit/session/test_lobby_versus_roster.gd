extends GutTest

## #554 — the lobby is what puts a human at a FOREIGN peer id in the roster, and
## that is what makes a [SeatPolicy] capable of being anything but a couch.
##
## Pure logic: [method LobbyScreen.build_participants] and
## [method LobbyScreen.resolve_mode] are static so the roster/seat/mode wiring
## is pinned without instancing a menu. The end-to-end two-process claims
## (#554 acceptance 1 and 3) wait on #533's harness; acceptance 2 and 4 are here.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _PLAYER := preload("res://entity/factions/player.tres")


func _entity(id: int) -> Entity:
	var e := Entity.new()
	e.entity_id = id
	e.is_human_controlled = true
	autofree(e)
	return e


func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


func _roster_of(participants: Array[Participant]) -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for p in participants:
		roster.add(p)
	return roster


# --- The three lobby shapes -----------------------------------------------

func test_single_player_lobby_is_one_local_human_plus_the_ai_count() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.SINGLE, NetworkConfig.offline(), 2)
	var humans := _humans(parts)
	assert_eq(humans.size(), 1)
	assert_eq(humans[0].kind, Participant.Kind.HUMAN)
	assert_eq(humans[0].camp, _PLAYER)
	assert_eq(parts.size(), 3, "one human plus two AI opponents")
	for i in range(1, parts.size()):
		assert_eq(parts[i].kind, Participant.Kind.AI)
		assert_eq(parts[i].camp, _NPC, "AI opponents share one rival camp")


func test_hot_seat_lobby_is_two_locals_on_one_camp() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline(), 0)
	assert_eq(parts.size(), 2)
	for p in parts:
		assert_eq(p.kind, Participant.Kind.HUMAN)
		assert_eq(p.camp, _CAMP_1, "hot-seat coop is two allied humans sharing territory")
		assert_eq(p.peer_id, 0, "offline, every seat is at this keyboard")


## The change #554 is actually about: a networked lobby seats a second human at
## another peer id, on its own camp, before anybody has connected — because procgen reads the
## camp shape at level setup, long before a socket lands.
func test_a_host_lobby_seats_a_remote_human_on_its_own_camp() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 0)
	assert_eq(parts.size(), 2)
	assert_eq(parts[0].kind, Participant.Kind.HUMAN)
	assert_eq(parts[0].camp, _CAMP_1)
	assert_eq(parts[0].peer_id, NetworkTransport.HOST_PEER_ID, "a host is always peer 1")
	assert_eq(parts[1].kind, Participant.Kind.HUMAN)
	assert_eq(parts[1].camp, _CAMP_2, "the joiner is a rival, not a couch partner")
	assert_true(parts[1].peer_id != parts[0].peer_id,
			"a pending remote seat must never read as this machine's")


func test_a_join_lobby_mirrors_the_host_shape() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join("127.0.0.1"), 0)
	assert_eq(parts.size(), 2)
	assert_eq(parts[1].kind, Participant.Kind.HUMAN)
	assert_eq(parts[1].peer_id, NetworkTransport.HOST_PEER_ID,
			"from a client, the remote human IS the host")


# --- #554 D3: the mode is derived from the roster, at START ----------------

func test_mode_is_versus_when_the_humans_span_more_than_one_camp() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 1)
	assert_eq(LobbyScreen.resolve_mode(parts), RunConfig.Mode.VERSUS)


func test_mode_is_coop_when_the_humans_share_a_camp() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline(), 1)
	assert_eq(LobbyScreen.resolve_mode(parts), RunConfig.Mode.COOP_HOTSEAT)


func test_mode_is_single_for_one_human_however_many_ai() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.SINGLE, NetworkConfig.offline(), 4)
	assert_eq(LobbyScreen.resolve_mode(parts), RunConfig.Mode.SINGLE,
			"four AI opponents are still a single-player run")


# --- #554 acceptance 4: the roster now yields a SEAT ----------------------

## The whole point of the unit, in one test. Before #554 every lobby-built
## participant was a human at peer_id 0, so `from_roster` returned a couch
## by construction and two peers each believed they drove the only human.
func test_a_host_roster_yields_a_seat_not_a_couch() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 1)
	var roster := _roster_of(parts)
	var mine := _entity(11)
	var theirs := _entity(22)
	var policy := SeatPolicy.from_roster(
			{parts[0].id: mine, parts[1].id: theirs},
			roster,
			NetworkTransport.HOST_PEER_ID)
	assert_eq(policy.seating, SeatPolicy.Seating.SEAT,
			"a remote human in the roster is what makes this machine a seat")
	assert_eq(policy.seated_entity_id, mine.entity_id)
	assert_false(policy.follows_active_turn(), "behind a wire the view stays mine")
	assert_false(policy.seats(theirs), "neither machine may act for the other's entity")


## The client half of the same roster, as it arrives over the wire: the host's
## participants verbatim, read against the client's own peer id.
func test_the_same_roster_seats_the_client_on_the_other_entity() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 1)
	var client_peer_id := 4711
	parts[1].peer_id = client_peer_id  # what the join stamps, host-side
	var host_entity := _entity(11)
	var client_entity := _entity(22)
	var policy := SeatPolicy.from_roster(
			{parts[0].id: host_entity, parts[1].id: client_entity},
			_roster_of(parts),
			client_peer_id)
	assert_eq(policy.seating, SeatPolicy.Seating.SEAT)
	assert_eq(policy.seated_entity_id, client_entity.entity_id,
			"the client is seated on ITS hero, from the host's own roster")


func test_an_offline_lobby_stays_a_couch() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline(), 1)
	var policy := SeatPolicy.from_roster(
			{parts[0].id: _entity(11), parts[1].id: _entity(22)}, _roster_of(parts), 0)
	assert_eq(policy.seating, SeatPolicy.Seating.COUCH,
			"two humans at one keyboard is what a couch IS")


## The roster crosses the wire by value (#528), and a pending/stamped peer id
## must survive that trip — a mode that agreed but a peer id that did not would
## desync silently.
func test_a_versus_roster_survives_the_wire() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 1)
	parts[1].peer_id = 4711
	var decoded := ParticipantRoster.from_dict(_roster_of(parts).to_dict())
	var rows := decoded.all()
	assert_eq(rows.size(), parts.size())
	for i in rows.size():
		assert_eq(rows[i].kind, parts[i].kind)
		assert_eq(rows[i].peer_id, parts[i].peer_id)
		assert_eq(rows[i].camp, parts[i].camp)


# --- #554 D2: the join stamps the seat the lobby already authored ----------

func test_the_join_stamps_the_pending_remote_seat() -> void:
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(), 1)
	var roster := _roster_of(parts)
	var pending: Participant = parts[1]
	assert_true(LobbyScreen.is_pending_remote(pending), "authored, nobody home yet")

	assert_true(LobbyScreen.stamp_pending_remote(roster, 4711))
	assert_eq(pending.peer_id, 4711)
	assert_false(LobbyScreen.is_pending_remote(pending))
	assert_false(LobbyScreen.stamp_pending_remote(roster, 4712),
			"a second peer has no seat waiting for it on a two-seat lobby")


func test_stamping_an_offline_roster_finds_nothing() -> void:
	var roster := _roster_of(LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline(), 1))
	assert_false(LobbyScreen.stamp_pending_remote(roster, 4711))
	assert_false(LobbyScreen.stamp_pending_remote(null, 4711))
