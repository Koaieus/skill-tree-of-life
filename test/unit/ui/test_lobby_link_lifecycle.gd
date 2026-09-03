extends GutTest

## #716 in the lobby: a joiner clears the build gate before it is seated, a
## dropped peer's seat goes back to waiting, and a client whose link dies is
## told so on screen. #736 adds the host-side half of that same gap: a peer
## that connected but has not cleared yet blocks START, out loud, until it
## clears, is refused, or the connection itself gives up on it.
##
## [b]Three lobbies, one host.[/b] `test_lobby_replication.gd` is the two-lobby
## fixture and stays that shape — one host, one client, one rule set. Everything
## here needs a THIRD screen, because every claim is about what happens to the
## OTHER client while one of them is refused or dropped, and a pair cannot say
## that. [method LoopbackTransport.attach] mints the extra end.
##
## No [Wire] and no socket, same as the file it sits beside: the lobby never
## opens a link, it only binds one that is live.

const _PEER_A := 2
const _PEER_B := 3
## The remote seat's id in a two-human roster — [method
## LobbyScreen.build_participants] authors it second.
const _REMOTE_SEAT := 2

var _host_transport: LoopbackTransport
var _a_transport: LoopbackTransport
var _b_transport: LoopbackTransport

var _host: LobbyScreen
var _a: LobbyScreen
var _b: LobbyScreen


func before_each() -> void:
	var pair := LoopbackTransport.pair()
	_host_transport = pair[0]
	_a_transport = pair[1]
	_b_transport = LoopbackTransport.attach(_host_transport, _PEER_B)
	for t in [_host_transport, _a_transport, _b_transport]:
		add_child_autofree(t)

	_host = _lobby(NetworkConfig.host(0))
	_a = _lobby(NetworkConfig.join("127.0.0.1", 0))
	_b = _lobby(NetworkConfig.join("127.0.0.1", 0))
	_host.bind_link(_host_transport)
	_a.bind_link(_a_transport)
	_b.bind_link(_b_transport)


func _lobby(network: NetworkConfig) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, network)
	add_child_autofree(lobby)
	return lobby


func _seat_of(lobby: LobbyScreen, id: int) -> Participant:
	for p in lobby.participants():
		if p.id == id:
			return p
	return null


## What a completed dial emits, and the whole handshake falls out of it: the
## client announces its stamp, the host gates it, the roster comes back.
func _join(transport: LoopbackTransport) -> void:
	transport.announce_joined()


## Stage a build mismatch on [param lobby]. The link is reachable because
## [method LobbyScreen.bind_link] holds it, and a stamp set after `add_child`
## is how every other build-gate fixture stages this without two checkouts.
static func _mismatch(lobby: LobbyScreen) -> void:
	lobby._link.build_stamp = {
		CommandLink.BUILD_SHA: "54cfcd7",
		CommandLink.BUILD_BRANCH: "master",
		CommandLink.BUILD_WORKTREE: "issue-716",
	}


# --- acceptance 2: cleared, then seated. Never the other way round -----------

## The join is two events now, and the seat hangs off the SECOND one. A socket
## join says somebody connected; it does not say they are running this code.
func test_a_peer_that_has_not_cleared_is_not_seated_and_no_roster_goes_out() -> void:
	var rosters: Array[int] = []
	_a_transport.message_received.connect(func(_p: Dictionary): rosters.append(1))

	_host._on_link_peer_joined(_PEER_A)

	assert_true(LobbyScreen.is_pending_remote(_seat_of(_host, _REMOTE_SEAT)),
			"the bare join seats nobody")
	assert_eq(rosters, [], "and broadcasts nothing — not even a roster to take back")


func test_clearing_the_gate_seats_the_peer_and_replicates() -> void:
	_join(_a_transport)

	assert_eq(_seat_of(_host, _REMOTE_SEAT).peer_id, _PEER_A, "the waiting seat is stamped")
	assert_eq(_seat_of(_a, _REMOTE_SEAT).peer_id, _PEER_A,
			"and the joiner is showing the host's roster")
	assert_eq(_host.status_text(), "", "nothing went wrong, so nothing is said")


## Acceptance 1 and 2 together, at the screen. The refused peer is never in
## anybody's roster — not for one broadcast — the host names it and the reason,
## the refused client is told why, and the client that cleared is untouched.
func test_a_refused_joiner_is_never_seated_and_the_other_client_is_untouched() -> void:
	_join(_a_transport)
	var seated_a: int = _seat_of(_a, _REMOTE_SEAT).peer_id
	_mismatch(_b)

	_join(_b_transport)

	assert_eq(_seat_of(_host, _REMOTE_SEAT).peer_id, _PEER_A,
			"the seat still belongs to the client that cleared")
	assert_string_contains(_host.status_text(), str(_PEER_B))
	assert_string_contains(_host.status_text(), "build mismatch")
	assert_string_contains(_b.status_text(), "build mismatch")
	assert_string_contains(_b.status_text(), "Refused")

	assert_eq(_seat_of(_a, _REMOTE_SEAT).peer_id, seated_a,
			"and the innocent client's roster never moved")
	assert_eq(_a.status_text(), "", "nor was it told anything had gone wrong")
	assert_true(_a_transport.is_linked(), "its link is still up")
	assert_true(_host_transport.is_linked(), "and so is the host's")


# --- #736: a peer connected-but-not-cleared refuses START, and says why ------
#
# The bare join above (acceptance 2) seats nobody but is not a no-op any more:
# it is the exact window a host pressing START used to broadcast a roster the
# joiner could not find itself in. Owner call, 2026-09-03, fork 2: refuse START
# only while this window is open, and surface why (fork 3) — solo hosting with
# nobody connecting at all stays legal, which every OTHER test in this file
# already exercises by never seeing `_host.can_start()` go false on its own.

func test_a_connecting_peer_blocks_start_and_says_why() -> void:
	assert_true(_host.can_start(), "sanity: nobody has connected yet")

	_host._on_link_peer_joined(_PEER_A)

	assert_false(_host.can_start(), "a socket connected but has not cleared the gate")
	assert_true(_host._start_button.disabled)
	assert_string_contains(_host.status_text(), "Waiting for 1 peer",
			"fork 3: the refusal is said out loud, not only returned")


## The gate opens again the instant the peer clears — [method
## test_clearing_the_gate_seats_the_peer_and_replicates] pins the roster half of
## this same call; this pins the START half.
func test_clearing_the_gate_unblocks_start() -> void:
	_host._on_link_peer_joined(_PEER_A)
	assert_false(_host.can_start())

	_join(_a_transport)

	assert_true(_host.can_start(), "cleared — the wait this connect opened is over")
	assert_eq(_host.status_text(), "", "and the transient line clears with it")


## A refused peer is disconnected as part of being refused ([method
## CommandLink._refuse_peer]) — the window it opened at `peer_joined` must
## close with it rather than leaving START stuck refused for a connection that
## no longer exists.
func test_a_refused_peer_unblocks_start_too() -> void:
	_mismatch(_a)

	_join(_a_transport)

	assert_true(_host.can_start(),
			"the refusal's own disconnect closed the #736 window it opened")
	assert_string_contains(_host.status_text(), "Refused",
			"the refusal line still wins over the now-empty wait")


## The window's last removal path: a peer that connects and then never sends a
## byte — no clear, no refusal — still leaves via [signal
## NetworkTransport.peer_left] once the transport gives up on it (ENet's own
## keepalive in production; driven here the same way
## [method test_dropping_a_peer_at_the_transport_returns_its_seat_to_waiting]
## drives an already-seated drop). Without this path #736's fix would trade a
## silent unplayable run for a START button bricked by a peer that vanished
## before ever announcing itself.
func test_a_connecting_peer_that_vanishes_unblocks_start() -> void:
	_host._on_link_peer_joined(_PEER_A)
	assert_false(_host.can_start())

	_host_transport.drop_peer(_PEER_A)

	assert_true(_host.can_start(), "the dead connection's hold on START is gone with it")


# --- item 3: a drop returns the seat to waiting ------------------------------

## Driven from the TRANSPORT, not by calling the handler: `Wire.drop_peer` /
## `LoopbackTransport.drop_peer` is what a real disconnect goes through, and the
## claim being made is that `peer_left` reaches the lobby at all — the signal
## nothing outside the transport was connected to before #716.
func test_dropping_a_peer_at_the_transport_returns_its_seat_to_waiting() -> void:
	_join(_a_transport)
	# The second client is here only to observe: acceptance 4 is that the seat
	# goes back to waiting on the host AND on every other client.
	_join(_b_transport)
	assert_eq(_seat_of(_host, _REMOTE_SEAT).peer_id, _PEER_A, "sanity: A holds the seat")
	var seen: Array[Dictionary] = []
	_b_transport.message_received.connect(func(p: Dictionary): seen.append(p))

	_host_transport.drop_peer(_PEER_A)

	assert_true(LobbyScreen.is_pending_remote(_seat_of(_host, _REMOTE_SEAT)),
			"the seat is waiting again rather than gone")
	assert_eq(_host.participants().size(), 2 + LobbyScreen.DEFAULT_AI_OPPONENTS,
			"two humans and the offered AI count, still")
	assert_eq(seen.size(), 1, "and exactly one roster went out for it")
	assert_true(LobbyScreen.is_pending_remote(_seat_of(_b, _REMOTE_SEAT)),
			"which the other client is now showing")


# --- item 4: the client is told its link died --------------------------------

func test_a_client_whose_link_dies_says_so_and_cannot_start() -> void:
	_join(_a_transport)
	assert_eq(_a.status_text(), "", "sanity: nothing wrong yet")

	_host_transport.drop_peer(_PEER_A)

	assert_string_contains(_a.status_text(), "Connection lost")
	assert_string_contains(_a.status_text(), "dropped by host")
	assert_true(_a._start_button.disabled,
			"START cannot open a run whose other seat can no longer arrive")


## A refusal is a verdict about the code being run, not a dead connection, so it
## gets its own sentence — "connection lost" over a build mismatch would send the
## operator to look at the network. The disconnect that ENFORCES the refusal
## arrives a line later and must not paint over the only account of the cause,
## though it still disables START, because the link really is gone.
func test_a_refusal_and_a_lost_link_read_differently() -> void:
	_mismatch(_b)

	_join(_b_transport)

	assert_string_contains(_b.status_text(), "Refused")
	assert_false(_b.status_text().contains("Connection lost"),
			"the generic line must not overwrite the specific one")
	assert_true(_b._start_button.disabled, "and the refused client cannot start a run")
