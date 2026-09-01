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


func before_each() -> void:
	Wire.stop()


func after_each() -> void:
	Wire.stop()


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


func test_a_freed_transport_stops_forwarding() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := EnetTransport.new()
	add_child(transport)
	transport.start_host(_EPHEMERAL)
	transport.free()
	await get_tree().process_frame

	# The assertion is that this does not fault on a freed listener — an
	# unbind that never ran shows up as an error, not as a failed compare.
	Wire.message_received.emit({"kind": "hello"})
	assert_true(Wire.is_open(), "the wire is still healthy with its listener gone")


func test_stopping_through_the_seam_closes_the_underlying_socket() -> void:
	Wire.start_host(_EPHEMERAL)
	var transport := _mounted()
	transport.start_host(_EPHEMERAL)

	transport.stop()

	assert_false(Wire.is_open(), "stop() still means stop")
	assert_eq(transport.role, NetworkTransport.Role.OFFLINE)
	assert_eq(Wire.local_peer_id(), 0, "a closed link is nobody")
