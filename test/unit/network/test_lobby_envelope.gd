extends GutTest

## #714: the two lobby envelopes, on the wire and nowhere near a world.
##
## [b]What this file pins that no other network test can.[/b] Every other kind
## the level link carries needs a [Graph], a [CommandApplier], or both — these two
## need neither, and that is the property under test as much as the round trip
## is: a lobby has no world, so a [LobbyChannel] on `lobby_link.tscn`, with no graph and
## no applier, must still carry a roster in both directions.
##
## The direction gates are the other half. [constant LobbyChannel.KIND_LOBBY] is
## the exact inverse of [constant LobbyChannel.KIND_LOBBY_PICK] — down under
## BROADCAST, up under MIRROR — because a pick is an INTENT and the roster is its
## confirmation (`docs/domain/multiplayer-sync-model.md`).

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _CORE := preload("res://entity/core/balanced_core.tres")

const _LOBBY_LINK := preload("res://network/lobby_link.tscn")

var _host: LobbyChannel
var _client: LobbyChannel
var _host_transport: LoopbackTransport
var _client_transport: LoopbackTransport


func before_each() -> void:
	var pair := LoopbackTransport.pair()
	_host_transport = pair[0]
	_client_transport = pair[1]
	add_child_autofree(_host_transport)
	add_child_autofree(_client_transport)
	_host = _link_on(_host_transport, NetworkConfig.Role.HOST)
	_client = _link_on(_client_transport, NetworkConfig.Role.CLIENT)


func _link_on(transport: LoopbackTransport, mode: NetworkConfig.Role) -> LobbyChannel:
	var link: NetworkLink = _LOBBY_LINK.instantiate()
	link.transport = transport
	add_child_autofree(link)
	link.role = mode
	var channel := link.channel_for(LobbyChannel.KIND_LOBBY) as LobbyChannel
	assert_not_null(channel, "the scene registers its LobbyChannel on the core")
	return channel


static func _seat(id: int, name_text: String, camp: Faction, peer_id: int) -> Participant:
	var p := Participant.new()
	p.id = id
	p.display_name = name_text
	p.camp = camp
	p.core_class = _CORE
	p.color = Color(0.25 * id, 0.5, 0.75)
	p.peer_id = peer_id
	return p


static func _two_seat_roster() -> ParticipantRoster:
	return ParticipantRoster.of([
		_seat(1, "Player 1", _CAMP_1, 1),
		_seat(2, "Player 2", _CAMP_2, 4711),
	] as Array[Participant])


## The whole roster crosses down, decodes back into equal rows, and arrives as a
## [ParticipantRoster] rather than a raw payload — the lobby listens on the
## signal, never on the envelope.
func test_the_host_s_roster_crosses_down_whole() -> void:
	var seen: Array[ParticipantRoster] = []
	_client.lobby_roster_received.connect(func(r: ParticipantRoster): seen.append(r))

	_host.send_lobby_roster(_two_seat_roster())

	assert_eq(seen.size(), 1, "the client got exactly one roster")
	var rows := seen[0].all()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].display_name, "Player 1")
	assert_eq(rows[0].peer_id, 1)
	assert_eq(rows[1].camp, _CAMP_2, "a Faction crosses as a path and loads back to the SAME resource")
	assert_eq(rows[1].core_class, _CORE)
	assert_eq(rows[1].peer_id, 4711, "the joiner's minted id crossed intact")


## A link with no world at all carries it. This is the difference from
## the setup kind, which lands in [GameSession] and opens a
## run; #714 acceptance 7 is that a lobby message does neither.
func test_a_lobby_roster_needs_no_graph_no_applier_and_opens_no_run() -> void:
	assert_false("graph" in _host.link, "sanity: the lobby link has no world")
	assert_null(_client.link.channel_for(CommandChannel.KIND_COMMAND), "sanity: and no command channel, so no applier")
	var run_started_seen: Array[bool] = []
	var handler := func(_cfg: RunConfig): run_started_seen.append(true)
	GameSession.run_started.connect(handler)

	_host.send_lobby_roster(_two_seat_roster())

	GameSession.run_started.disconnect(handler)
	assert_true(run_started_seen.is_empty(), "no lobby traffic opens a run")


## Up under MIRROR only. A pick is what a client says; a host saying one would be
## the authority asking itself for permission.
func test_a_pick_crosses_up_and_only_from_a_client() -> void:
	var seen: Array[Dictionary] = []
	_host.lobby_pick_received.connect(func(p: Dictionary): seen.append(p))

	_client.send_lobby_pick({"id": 2, "peer_id": 4711, "color": Color.RED})
	assert_eq(seen.size(), 1, "the host got the client's pick")
	assert_eq(int(seen[0]["id"]), 2)
	assert_eq(seen[0]["color"], Color.RED)

	_host.send_lobby_pick({"id": 1, "peer_id": 1, "color": Color.BLUE})
	assert_eq(seen.size(), 1, "a BROADCAST link sends no pick")


## Down under BROADCAST only, and applied under MIRROR only — the inverse gate.
func test_a_roster_travels_down_only() -> void:
	var seen: Array[ParticipantRoster] = []
	_host.lobby_roster_received.connect(func(r: ParticipantRoster): seen.append(r))

	_client.send_lobby_roster(_two_seat_roster())

	assert_true(seen.is_empty(), "a MIRROR link neither sends nor applies a roster")


## A pick with nothing in it is dropped rather than raising an empty change on
## the host — the one shape a hand-built payload can take that would otherwise
## cost a roster broadcast for nothing.
func test_an_empty_pick_is_dropped() -> void:
	var seen: Array[Dictionary] = []
	_host.lobby_pick_received.connect(func(p: Dictionary): seen.append(p))

	_client.send_lobby_pick({})
	_host_transport.message_received.emit(
			{NetworkLink.KEY_KIND: LobbyChannel.KIND_LOBBY_PICK, LobbyChannel.KEY_PICK: {}})

	assert_true(seen.is_empty(), "nothing to apply, nothing raised")


## The roster's array-shaped constructor, which is the only reason the lobby —
## which holds its seats as a plain [Array] — can reach [method
## ParticipantRoster.to_dict] at all.
func test_of_builds_a_roster_that_announced_every_row() -> void:
	var joined: Array[Participant] = []
	var seats: Array[Participant] = [_seat(1, "A", _CAMP_1, 1), _seat(2, "B", _CAMP_2, 2)]
	var roster := ParticipantRoster.new()
	roster.participant_joined.connect(func(p: Participant): joined.append(p))
	for p in seats:
		roster.add(p)

	var built := ParticipantRoster.of(seats)

	assert_eq(built.all().size(), 2)
	assert_eq(built.all()[1].display_name, "B")
	assert_eq(joined.size(), 2, "add() is the one route in, for both")
