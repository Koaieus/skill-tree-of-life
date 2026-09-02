extends GutTest

## #714: two lobbies, one wire, one rule set.
##
## [b]Two [LobbyScreen]s in one process, faced at each other over a
## [LoopbackTransport] pair[/b] — the same headless fixture every other leg of the
## wire is tested through. No socket, no second OS process, and no [Wire]: the
## lobby never opens a link (that is `meta_root.gd`'s call), it only binds to one
## that is live, so [method LobbyScreen.bind_link] is all a test needs.
##
## What is being pinned is that there is exactly ONE rule set. A remote pick goes
## through `_on_color_picked` / `_on_core_class_picked` / `_on_camp_picked` — the
## very writers a local pick goes through — so colour uniqueness and the
## [LobbyPolicy] START veto apply to a client's pick without either being
## restated for the wire.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _NINJA_OR_WHATEVER := preload("res://entity/core/basic_enemy_core.tres")

## The id a paired [LoopbackTransport] client answers to.
const _CLIENT_PEER := 2

var _host: LobbyScreen
var _client: LobbyScreen
var _pair: Array[LoopbackTransport] = []


func before_each() -> void:
	GameSession.end()
	_build(null)


## #715 put a [signal GameSession.run_started] listener on every linked lobby, so
## a run left open here would leak into the next test's fixture.
func after_each() -> void:
	GameSession.end()


## Both lobbies, wired. [param policy] is authored per shape and reaches both
## screens, exactly as a [MenuGraph.Route] would hand the same resource to the
## HOST and JOIN leaves.
func _build(policy: LobbyPolicy) -> void:
	_pair = LoopbackTransport.pair()
	add_child_autofree(_pair[0])
	add_child_autofree(_pair[1])
	_host = _lobby(NetworkConfig.host(0), policy)
	_client = _lobby(NetworkConfig.join("127.0.0.1", 0), policy)
	_host.bind_link(_pair[0])
	_client.bind_link(_pair[1])


## The join, driven from the CLIENT's socket event rather than by calling the
## host's handler (#716). Since the build gate moved host-side and per peer, a
## seat is offered on [signal CommandLink.peer_cleared] and not on the bare join
## — so a fixture that pokes `_on_link_peer_joined` directly would be asserting
## against a path production no longer takes. `announce_joined` is exactly what
## a completed dial emits, and the announce, the gate and the roster answer all
## fall out of it.
func _join() -> void:
	_pair[1].announce_joined()


func _lobby(network: NetworkConfig, policy: LobbyPolicy) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, network, policy)
	add_child_autofree(lobby)
	return lobby


static func _versus_policy() -> LobbyPolicy:
	var policy := LobbyPolicy.new()
	policy.camps = [_CAMP_1, _CAMP_2]
	policy.human_camps_pickable = true
	policy.require_distinct_human_camps = true
	return policy


## The seat this lobby's own machine sits at, once the link has stamped ids.
func _my_seat(lobby: LobbyScreen) -> Participant:
	for p in lobby.participants():
		if p.kind != Participant.Kind.AI and p.is_local(lobby._local_peer_id()):
			return p
	return null


func _seat_of(lobby: LobbyScreen, id: int) -> Participant:
	for p in lobby.participants():
		if p.id == id:
			return p
	return null


## The join, both ways at once (#714 acceptance 1). The host's waiting seat gets
## the arriving peer's id — [method LobbyScreen.stamp_pending_remote_peer]'s
## first caller outside its own file, at LOBBY time rather than level time
## (acceptance 5) — and the roster that goes out in response is what the joiner
## then shows, before any level exists.
func test_a_join_stamps_the_host_s_waiting_seat_and_replicates_the_roster() -> void:
	assert_true(LobbyScreen.is_pending_remote(_seat_of(_host, 2)),
			"sanity: seat 2 is the authored-up-front remote seat, still waiting")

	_join()

	assert_eq(_seat_of(_host, 2).peer_id, _CLIENT_PEER, "the waiting seat is stamped")
	assert_false(LobbyScreen.is_pending_remote(_seat_of(_host, 2)))
	# And the client is now showing the host's roster, not the one it authored.
	assert_eq(_seat_of(_client, 1).peer_id, NetworkTransport.HOST_PEER_ID,
			"the host's own row crossed with the host's id on it")
	assert_eq(_seat_of(_client, 2).peer_id, _CLIENT_PEER,
			"and the joiner's row carries the id the host stamped")


## A drop puts the seat back to waiting rather than deleting it: #554 D2 authored
## the seat up front so procgen could see it, and only the identity was ever
## outstanding.
func test_a_drop_returns_the_seat_to_waiting() -> void:
	_join()
	_host._on_link_peer_left(_CLIENT_PEER)

	assert_true(LobbyScreen.is_pending_remote(_seat_of(_host, 2)))
	assert_eq(_host.participants().size(), 3, "two humans and one AI, still")


## Acceptance 2, upward: the client picks, the host's row moves. And the client's
## OWN view moved only because the host said so — there is no local
## pre-application (#548 D5 at the roster's scope).
func test_a_client_s_pick_is_applied_by_the_host_and_comes_back_down() -> void:
	_join()
	var mine := _my_seat(_client)
	assert_eq(mine.id, 2, "the joiner's own seat is the one the host stamped")
	var wanted := Color(0.123, 0.456, 0.789)

	_client._on_row_color_picked(wanted, mine)

	assert_eq(_seat_of(_host, 2).color, wanted, "the host applied the client's pick")
	assert_eq(_seat_of(_client, 2).color, wanted, "and answered with it")

	_client._on_row_core_class_picked(_NINJA_OR_WHATEVER, _my_seat(_client))
	assert_eq(_seat_of(_host, 2).core_class, _NINJA_OR_WHATEVER,
			"a CoreClass crosses as a path and loads back to the same resource")


## Acceptance 2, downward.
func test_a_host_pick_reaches_the_joiner() -> void:
	_join()
	var wanted := Color(0.9, 0.1, 0.2)

	_host._on_row_color_picked(wanted, _seat_of(_host, 1))

	assert_eq(_seat_of(_client, 1).color, wanted)


## Acceptance 3. The uniqueness rule is [method LobbyScreen.taken_colors] — the
## same call that greys the chip out in a local picker — so a remote pick meets
## it without the wire restating it, and the host's answer is what the client
## ends up showing.
func test_a_colliding_colour_is_refused_and_the_client_converges() -> void:
	_join()
	var host_color: Color = _seat_of(_host, 1).color
	var before: Color = _seat_of(_client, 2).color
	assert_ne(before, host_color, "sanity: the palette handed the two seats different colours")

	_client._on_row_color_picked(host_color, _my_seat(_client))

	assert_eq(_seat_of(_host, 2).color, before, "the host refused a colour already taken")
	assert_eq(_seat_of(_client, 2).color, before,
			"and the client converged on the host's answer rather than keeping its own")
	assert_eq(_seat_of(_host, 1).color, host_color, "the slot that holds it is untouched")


## Acceptance 4: the veto is a fact about the roster, so a roster a CLIENT made
## invalid is a roster the host may not start.
func test_a_start_veto_reflects_a_remote_camp_pick() -> void:
	_build(_versus_policy())
	_join()
	assert_true(_host.can_start(), "sanity: the two humans start on different camps")

	_client._on_row_camp_picked(_CAMP_1, _my_seat(_client))

	assert_eq(_seat_of(_host, 2).camp, _CAMP_1, "the host applied the camp pick")
	assert_false(_host.can_start(),
			"a client made the roster unstartable and the host's button follows")
	assert_false(_client.can_start(), "and the joiner sees the same verdict")


## Acceptance 6, on the wire. The host validates against the roster, not against
## what the payload claims — a client naming somebody else's seat is refused and
## answered with the truth.
func test_a_client_may_not_move_the_host_s_row_or_an_ai_row() -> void:
	_join()
	var host_color: Color = _seat_of(_host, 1).color
	var ai := _seat_of(_host, 3)
	assert_eq(ai.kind, Participant.Kind.AI, "sanity: seat 3 is the AI opponent")
	var ai_color: Color = ai.color

	_host._on_remote_pick(
			LobbyScreen.encode_pick(_seat_of(_client, 1), _CLIENT_PEER, {"color": Color.RED}))
	_host._on_remote_pick(
			LobbyScreen.encode_pick(_seat_of(_client, 3), _CLIENT_PEER, {"color": Color.RED}))

	assert_eq(_seat_of(_host, 1).color, host_color, "the host's own seat is not a client's to move")
	assert_eq(_seat_of(_host, 3).color, ai_color, "nor is an AI seat")


## Acceptance 6, in the UI, and it reads the same on both machines: a human seat
## is yours iff it is at your peer, and the AI belongs to whoever authors the
## roster. The rule is symmetric on purpose — the host does not get to dress the
## joiner's hero either, which is what makes a joiner's pick stick rather than
## race the host's.
func _color_pick_disabled(lobby: LobbyScreen, row: int) -> bool:
	return lobby._rows_container.get_child(row).get_node("%ColorPick").disabled


func test_only_the_local_seat_s_pickers_are_live() -> void:
	_join()

	assert_true(_color_pick_disabled(_client, 0), "the host's row is locked on the joiner's screen")
	assert_false(_color_pick_disabled(_client, 1), "the joiner's own row is live")
	assert_true(_color_pick_disabled(_client, 2),
			"an AI row belongs to whoever authors the roster, and that is not a client")

	assert_false(_color_pick_disabled(_host, 0), "the host's own row is live for the host")
	assert_true(_color_pick_disabled(_host, 1), "the joiner's seat is not the host's to dress")
	assert_false(_color_pick_disabled(_host, 2), "and the host does author the AI")


## The rule itself, without a lobby around it.
func test_may_edit_is_locality_for_humans_and_authorship_for_ai() -> void:
	var mine := Participant.new()
	mine.peer_id = 7
	var theirs := Participant.new()
	theirs.peer_id = 8
	var ai := Participant.new()
	ai.kind = Participant.Kind.AI

	assert_true(LobbyScreen.may_edit(mine, 7, false))
	assert_false(LobbyScreen.may_edit(theirs, 7, true))
	assert_true(LobbyScreen.may_edit(ai, 7, true), "an AI seat belongs to the roster's author")
	assert_false(LobbyScreen.may_edit(ai, 7, false), "and a client does not author it")
	assert_false(LobbyScreen.may_edit(null, 7, true))


## Peer `0` is "no link", and every offline seat carries it — a payload claiming
## it must never match a row, or an offline roster would be remotely editable by
## anyone who could reach the port.
func test_a_remote_pick_from_peer_zero_is_refused() -> void:
	var seat := Participant.new()
	seat.peer_id = 0

	assert_false(LobbyScreen.may_edit_remotely(seat, 0))
	assert_false(LobbyScreen.may_edit_remotely(null, 4))
	seat.peer_id = 4
	assert_true(LobbyScreen.may_edit_remotely(seat, 4))
	assert_false(LobbyScreen.may_edit_remotely(seat, 5))


## Acceptance 8. An offline lobby mounts no link at all — not a link in
## [constant CommandLink.Mode.OFF], no transport, no traffic, and every row still
## editable, which is the whole hot-seat shape.
func test_an_offline_lobby_mounts_nothing() -> void:
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT)
	add_child_autofree(lobby)

	assert_null(lobby._link, "no link")
	assert_null(lobby._transport, "no transport")
	assert_eq(lobby._local_peer_id(), 0, "and this machine is nobody on a wire that isn't there")
	for i in lobby._rows_container.get_child_count():
		assert_false(lobby._rows_container.get_child(i).get_node("%ColorPick").disabled,
				"every slot stays this machine's to author (row %d)" % i)


## Acceptance 7, at the lobby's own scope: START is the only thing that opens a
## run, and the lobby hands its own link back before it fires so the level can
## adopt the socket without a second [CommandLink] answering on it.
## [b]Re-pointed by #715[/b], which moved the release one signal later. The
## button no longer releases: it only emits, and the shell answers by opening the
## run — which is the moment the HOST has a resolved seed to broadcast, and so
## the moment both machines may leave the menu. The claim is unchanged; what it
## hangs off is [signal GameSession.run_started].
func test_start_releases_the_link_without_closing_the_socket() -> void:
	_join()
	var transport := _host._transport
	var configs: Array[RunConfig] = []
	_host.start_pressed.connect(func(cfg: RunConfig): configs.append(cfg))

	_host._on_start_button_pressed()
	assert_eq(configs.size(), 1, "START still emits its RunConfig")
	assert_not_null(_host._link, "and does NOT release yet — the seed is not resolved")

	# What `meta_root._on_start_pressed` does next.
	GameSession.start(configs[0])

	assert_null(_host._link, "the lobby's link is gone once the run is open")
	assert_true(is_instance_valid(transport), "the transport it did not own is not freed")


## #715 acceptance 1, at the lobby's scope: START broadcasts the settled run over
## the live link, and the joiner leaves the menu because of it rather than
## because somebody pressed something.
##
## [b]The seed is the assertion that matters.[/b] `build_run_config` hands back a
## sentinel (`0` = randomise me) and [method GameSession.start] resolves it; a
## broadcast taken from the button rather than from the run would ship that
## sentinel, which [method GameSession.apply_received] refuses outright. So this
## also pins WHEN the broadcast happens, not only that it does.
func test_start_broadcasts_the_resolved_run_and_routes_the_joiner() -> void:
	_host._on_link_peer_joined(_CLIENT_PEER)
	var routed: Array[RunConfig] = []
	_client.remote_start.connect(func(cfg: RunConfig): routed.append(cfg))
	var configs: Array[RunConfig] = []
	_host.start_pressed.connect(func(cfg: RunConfig): configs.append(cfg))

	_host._on_start_button_pressed()
	GameSession.start(configs[0])

	assert_eq(routed.size(), 1, "the joiner was routed by the host's START, with no button of its own")
	assert_ne(routed[0].seed, 0,
			"and it adopted a RESOLVED seed — a sentinel is not a run")
	assert_eq(routed[0].seed, GameSession.config.seed, "the same one the host is playing")
	assert_null(_client._link, "the joiner released its own link too, so the level may adopt the socket")
