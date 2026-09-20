extends GutTest

## #713 — the socket and the RPC live at `/root/Wire`, so a link can exist
## before a level does and survive the transition into one.
##
## [b]What this file can and cannot prove in one process.[/b]
## `multiplayer.multiplayer_peer` is a [SceneTree] property, so one process holds
## exactly one link — a real host-and-client pair is the two-OS-process harness's
## job (`docs/domain/multiplayer-harness.md`), not a unit test's. What is pinned
## here is every half of the mechanism that used to be scene-coupled:
##
## - the socket outliving the node that used to own it (which IS the scene-change
##   mechanism: `SceneDirector.goto` frees the old scene, and before #713 that
##   freed the peer's owner, the RPC target and the peer list along with it);
## - a level ADOPTING a live link instead of restarting it — the failure this
##   most needs to catch, since [method Wire.start_host] opens with a `stop()`
##   and a blind re-start would tear down the link it was just handed;
## - the join replay, so a host that adopts still stamps rosters and ships run
##   setup for peers that arrived while the menu was up.
##
## [b]Peer arrivals are simulated by calling [Wire]'s own socket handlers.[/b]
## There is no second process to connect from, and the handlers are exactly what
## `multiplayer.peer_connected` invokes — so this tests the bookkeeping and the
## replay, and deliberately not ENet itself.

## Ephemeral, not [constant NetworkConfig.DEFAULT_PORT] (#581): a concurrent
## suite, or an earlier socket in this same run not yet released, can hold 9099.
const _EPHEMERAL := 0


## [b][Wire] is the second process-global autoload this suite has to reset.[/b]
## `test_link_mount.gd` already documents the hazard for `GameSession.network`
## — an autoload outlives every test in GUT's single process, so a leftover
## socket would make these assertions pass or fail on test ORDER. Any future
## file that opens one owes the same two hooks.
func before_each() -> void:
	Wire.stop()
	GameSession.network = null


func after_each() -> void:
	Wire.stop()
	GameSession.network = null


## A mounted transport, in the tree, as a level would hold one.
func _mounted() -> EnetTransport:
	var t := EnetTransport.new()
	t.name = "Transport"
	add_child_autofree(t)
	return t


# --- the socket exists before, and outlives, any level ----------------------

func test_the_singleton_opens_a_socket_with_no_level_anywhere() -> void:
	assert_false(Wire.is_open(), "sanity: nothing open yet")
	assert_eq(Wire.start_host(_EPHEMERAL), OK, "a host listens without a GameRoot in sight")
	assert_true(Wire.is_open(), "the socket is up")
	assert_false(Wire.is_linked(), "open is not linked — nobody has joined")
	assert_eq(Wire.role, NetworkTransport.Role.HOST)
	assert_eq(Wire.local_peer_id(), NetworkTransport.HOST_PEER_ID,
			"and this machine knows its own id before any level could ask")


## The regression the whole issue is about. `SceneDirector.goto` frees the
## outgoing scene; before #713 that took the peer's owner, the `@rpc` target and
## the peer list with it, so a lobby-time link could not have survived into a
## level even though the PEER itself always could.
func test_freeing_the_mounted_transport_does_not_close_the_socket() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := EnetTransport.new()
	add_child(transport)
	transport.start_host(_EPHEMERAL)
	assert_eq(transport.role, NetworkTransport.Role.HOST, "sanity: it adopted")

	transport.free()
	await get_tree().process_frame

	assert_true(Wire.is_open(), "the level went away; the link did not")
	assert_eq(Wire.local_peer_id(), NetworkTransport.HOST_PEER_ID, "and it is the same link")


# --- adopting a link this level did not open --------------------------------

func test_a_mounted_transport_adopts_a_live_host_link_instead_of_restarting_it() -> void:
	Wire.start_host(_EPHEMERAL)
	Wire._on_peer_connected(7)
	assert_true(Wire.is_linked(), "sanity: a peer joined while the menu was up")

	var transport := _mounted()
	assert_eq(transport.start_host(_EPHEMERAL), OK)

	assert_eq(transport.role, NetworkTransport.Role.HOST, "the facade mirrors the live role")
	assert_true(transport.is_linked(),
			"and it is linked on arrival — a re-start would have dropped peer 7")
	assert_eq(transport.local_peer_id(), NetworkTransport.HOST_PEER_ID)


func test_a_client_adopts_the_link_its_lobby_dialled() -> void:
	# No server to reach, so the dial only has to START — the socket exists and
	# the role is taken the moment `create_client` returns.
	Wire.start_client("127.0.0.1", 1)
	var transport := _mounted()

	assert_eq(transport.start_client("127.0.0.1", 1), OK)
	assert_eq(transport.role, NetworkTransport.Role.CLIENT)


## The join replay. Every host-side consequence of a peer arriving — stamping
## its roster seat, shipping the run setup — hangs off `peer_joined`, which fired
## while the menu was up and this node did not exist. Without the replay a level
## that adopts a link silently never greets the peers already on it.
func test_adopting_replays_the_peers_that_arrived_before_this_level() -> void:
	Wire.start_host(_EPHEMERAL)
	Wire._on_peer_connected(7)
	Wire._on_peer_connected(9)

	var transport := _mounted()
	var seen: Array[int] = []
	transport.peer_joined.connect(func(id: int): seen.append(id))
	transport.start_host(_EPHEMERAL)

	assert_eq(seen, [7, 9], "both pre-existing peers are handed up, in arrival order")


func test_a_level_that_wants_the_other_role_is_refused_rather_than_stealing_the_link() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := _mounted()

	assert_ne(transport.start_client("127.0.0.1", 1), OK,
			"a client mount must not silently take over a host's socket")
	assert_eq(Wire.role, NetworkTransport.Role.HOST, "and the live link is untouched")
	assert_true(Wire.is_open())


## The ordering [GameRoot._open_link] silently depends on. It connects BOTH
## `link_changed` -> `_greet_if_linked` (which ships the build-stamp hello) and
## `peer_joined` -> `_on_peer_joined` (which stamps the roster seat and ships the
## run setup). On a live link both fire inside one `start_host` call, and the
## hello has to be first — `docs/domain/multiplayer-harness.md` notes the gate
## must precede anything else crossing.
func test_adopting_announces_before_it_replays_a_join() -> void:
	Wire.start_host(_EPHEMERAL)
	Wire._on_peer_connected(7)

	var transport := _mounted()
	var order: Array[String] = []
	transport.link_changed.connect(func(_s: String): order.append("status"))
	transport.peer_joined.connect(func(_id: int): order.append("join"))
	transport.start_host(_EPHEMERAL)

	assert_eq(order, ["status", "join"],
			"the hello's trigger fires before the run setup's")


# --- the seam still behaves like a seam -------------------------------------

func test_a_wire_payload_surfaces_on_the_mounted_seam() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := _mounted()
	transport.start_host(_EPHEMERAL)

	var got: Array[Dictionary] = []
	transport.message_received.connect(func(p: Dictionary): got.append(p))
	Wire.message_received.emit({"kind": "hello"})

	assert_eq(got.size(), 1, "the facade forwards what the wire received")
	assert_eq(got[0].get("kind"), "hello")


## The unbind, asserted on the connection itself. [Wire] is an autoload that
## outlives every level, so a facade that failed to detach would accumulate one
## dead listener per level loaded — and because a stale connection surfaces as an
## engine error rather than a failed assert, nothing weaker than this catches it.
func test_a_freed_transport_detaches_from_the_wire() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := EnetTransport.new()
	add_child(transport)
	transport.start_host(_EPHEMERAL)
	assert_eq(Wire.message_received.get_connections().size(), 1, "sanity: bound")

	transport.free()
	await get_tree().process_frame

	assert_eq(Wire.message_received.get_connections().size(), 0,
			"a freed level leaves no listener behind on the singleton")
	assert_eq(Wire.peer_joined.get_connections().size(), 0)
	assert_eq(Wire.link_changed.get_connections().size(), 0)
	assert_true(Wire.is_open(), "and the link itself is untouched")


func test_stopping_through_the_seam_closes_the_underlying_socket() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := _mounted()
	transport.start_host(_EPHEMERAL)

	transport.stop()

	assert_false(Wire.is_open(), "stop() still means stop")
	assert_eq(transport.role, NetworkTransport.Role.OFFLINE)
	assert_eq(Wire.local_peer_id(), 0, "a closed link is nobody")


# --- #716 item 2: the socket stops on every leave ---------------------------

## Acceptance 3, on the run's exit. Both level exits go through
## [method GameSession.end] (`GameRoot.route_to_meta_now`, `PauseMenu.leave_run`),
## and until #716 it cleared the [NetworkConfig] and left the LISTENER up —
## harmless only while the socket died with the level, which stopped being true
## at #713.
##
## [b]The re-host is on the very port that was just held[/b], read back out of
## the socket ([method Wire.port]). Any other port would pass with the old
## behaviour too, which is precisely the assertion the issue asks for.
func test_leaving_a_run_stops_the_socket_and_frees_the_port() -> void:
	assert_eq(Wire.start_host(_EPHEMERAL), OK)
	var held := Wire.port()
	assert_gt(held, 0, "sanity: an ephemeral bind still lands on a real port")

	GameSession.end()

	assert_false(Wire.is_open(), "leaving the run took the listener down with it")
	assert_eq(Wire.start_host(held), OK,
			"and the next Host click binds the same port rather than failing on it")


## Dropping ONE peer leaves the link up for the rest (#716 item 1, at the socket
## seam), and does it on the spot: `disconnect_peer` only SCHEDULES the drop, and
## every caller wants "that peer is gone" to be true the instant it asked.
##
## [b]The ENet half is deliberately absent, as everywhere else in this file.[/b]
## The simulated peers were never in `ENetMultiplayerPeer`'s own list, so asking
## it to disconnect one is an engine error rather than a test signal; nulling the
## socket handle leaves exactly the bookkeeping this is about. What a real drop
## does to a real peer is pinned at the loopback seam instead
## (`test_link_lifecycle.gd`, `test_lobby_link_lifecycle.gd`).
func test_dropping_a_peer_is_immediate_and_leaves_the_link_up() -> void:
	Wire.start_host(_EPHEMERAL)
	Wire._on_peer_connected(7)
	Wire._on_peer_connected(9)
	Wire._peer = null
	var left: Array[int] = []
	Wire.peer_left.connect(func(id: int): left.append(id))

	Wire.drop_peer(7)

	assert_eq(left, [7], "the drop is announced by the call, not by a later poll")
	assert_eq(Wire.peers(), PackedInt32Array([9]), "and the other peer is untouched")
	assert_true(Wire.is_open(), "the listener never went down")


## …and ENet's own notification for a peer this machine already hung up on is
## swallowed, so a lobby seat cannot be returned to "waiting" twice — once per
## source of the same fact.
func test_a_peer_left_notification_fires_once_per_peer() -> void:
	Wire.start_host(_EPHEMERAL)
	Wire._on_peer_connected(7)
	var left: Array[int] = []
	Wire.peer_left.connect(func(id: int): left.append(id))

	Wire._on_peer_disconnected(7)
	Wire._on_peer_disconnected(7)

	assert_eq(left, [7])


## Item 4's ordering bug, at the seam that hid it. [Wire] announced BEFORE it
## stopped, so [method EnetTransport._on_wire_status] copied out a role that was
## about to be wrong and nothing above the seam ever learned the link had died.
func test_a_lost_link_reaches_the_seam_as_offline() -> void:
	Wire.start_client("127.0.0.1", 1)
	var transport := _mounted()
	transport.start_client("127.0.0.1", 1)
	var lost: Array[String] = []
	var roles: Array[int] = []
	transport.link_lost.connect(func(reason: String):
		lost.append(reason)
		roles.append(transport.role))

	Wire._on_server_disconnected()

	assert_eq(lost.size(), 1, "the facade re-emits the loss")
	assert_eq(roles, [NetworkTransport.Role.OFFLINE],
			"and by the time it does, the role it reports is already the true one")
	assert_false(Wire.is_open())
	assert_string_contains(Wire.last_status, "host went away")


# --- and the same thing through the real composition root -------------------

## Acceptance 2, through the caller that matters. The tests above drive the
## facade directly; this one goes through [method GameRoot._open_link], which
## connects its handlers BEFORE calling `start_host` and is the only production
## caller there is.
##
## [b]No peer is simulated here, on purpose.[/b] A peer in [Wire]'s book makes
## `send` real, and a `_receive.rpc()` aimed at an id no ENet peer answers to is
## an engine error rather than a test signal. Peer replay and its ordering are
## pinned above, on the seam, where they can be observed without a socket.
##
## The socket-identity assert is the one that matters: [method Wire.start_host]
## opens with a `stop()`, so a level that re-started rather than adopted would
## hold a DIFFERENT [ENetMultiplayerPeer] — and on a real link, a client that had
## already joined the lobby would have been dropped on the floor by the level it
## was joining.
func test_a_game_root_adopts_the_lobby_s_link_rather_than_reopening_it() -> void:
	Wire.start_host(_EPHEMERAL)
	var opened_by_the_lobby := Wire._peer
	assert_not_null(opened_by_the_lobby, "sanity: there is a socket to adopt")

	GameSession.network = NetworkConfig.host(_EPHEMERAL)
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	# The swap `level.tscn` and both harness scenes author in their `.tscn`, done
	# here in code so this test does not depend on which level happens to ship it.
	root.get_node("Transport").set_script(preload("res://network/enet_transport.gd"))
	add_child_autofree(root)
	await wait_physics_frames(6)

	assert_true(root.transport is EnetTransport, "sanity: the swap took")
	assert_eq(root.transport.role, NetworkTransport.Role.HOST,
			"the level took the role off the live link")
	assert_eq(root.command_link.mode, CommandLink.Mode.BROADCAST, "and it is the authority")
	assert_true(Wire.is_open(), "the link the lobby opened is still up")
	assert_eq(Wire._peer, opened_by_the_lobby,
			"and it is the SAME socket — a re-start would have dropped every "
			+ "peer that joined in the lobby")
