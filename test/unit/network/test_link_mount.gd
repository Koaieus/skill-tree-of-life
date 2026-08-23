extends GutTest

## #531 — the mounted wire's NODE PATH, which is the whole reason the mount
## exists.
##
## Godot resolves an RPC by node path ([EnetTransport]'s own docstring), so two
## peers running different scenes must still find `Transport` at the same place
## or the RPC silently goes nowhere — no error, no packet, a dead link. Nothing
## else in the suite would notice someone reparenting or renaming these two
## nodes, which is exactly the class of change that looks harmless in a diff.
##
## The harness is checked here too, and not as an afterthought: `mp_dev_sandbox`
## inherits `game_root.tscn`, so before #531 it authored its own pair and now it
## must SWAP the inherited transport's script instead. A test that only asserted
## "the harness's transport is an [EnetTransport]" would pass while a second,
## auto-renamed pair sat beside the first — hence the *count* assertions.

const GAME_ROOT := "res://scenes/game_root.tscn"
const MP_SANDBOX := "res://scenes/dev/mp_dev_sandbox.tscn"
const FIRST_LEVEL := "res://scenes/first_level_sandbox.tscn"

## Where every peer must find the pair. Change these and you have changed the
## wire protocol.
const TRANSPORT_PATH := "Transport"
const LINK_PATH := "CommandLink"


func before_each() -> void:
	# The role is an autoload field and an autoload outlives every test in GUT's
	# single process — a leftover HOST would make the "mounted idle" assertions
	# below pass or fail on test ORDER.
	GameSession.network = null


func after_each() -> void:
	GameSession.network = null


## A `game_root.tscn` whose `_ready` has run to COMPLETION. It is a coroutine
## with awaits in it (`_setup_level`, then a layout frame once the HUD composes)
## and `_open_link` sits past the last of them — a two-frame wait sees the role
## adopted but the socket not yet opened, which is a green test for a dead link.
func _live_game_root() -> GameRoot:
	var root: GameRoot = preload(GAME_ROOT).instantiate()
	add_child_autofree(root)
	await wait_frames(6)
	return root


## Direct children carrying a [NetworkTransport] / [CommandLink] script, by
## name — an added-instead-of-swapped pair shows up here as `Transport2`.
func _network_children(root: Node) -> Dictionary:
	var found := {"transport": [], "link": []}
	for child in root.get_children():
		if child is CommandLink:
			found["link"].append(String(child.name))
		elif child is NetworkTransport:
			found["transport"].append(String(child.name))
	return found


# --- the composition root ---------------------------------------------------

func test_game_root_mounts_the_pair_at_the_expected_path() -> void:
	var root: GameRoot = await _live_game_root()

	assert_not_null(root.get_node_or_null(TRANSPORT_PATH), "a transport at %s" % TRANSPORT_PATH)
	assert_not_null(root.get_node_or_null(LINK_PATH), "a link at %s" % LINK_PATH)
	assert_eq(root.transport, root.get_node(TRANSPORT_PATH), "%Transport is that node")
	assert_eq(root.command_link, root.get_node(LINK_PATH), "%CommandLink is that node")


func test_the_default_transport_is_the_loopback() -> void:
	# The seam's default, per #531: mounted in EVERY level so single-player and
	# hot-seat run the same wiring a networked run does. A level wanting a real
	# socket overrides this node's script.
	var root: GameRoot = await _live_game_root()
	assert_true(root.transport is LoopbackTransport,
			"default transport is a LoopbackTransport, got %s" % root.transport)


func test_the_mounted_link_is_wired_but_idle() -> void:
	var root: GameRoot = await _live_game_root()
	var link: CommandLink = root.command_link
	assert_eq(link.transport, root.transport, "transport NodePath")
	assert_eq(link.command_applier, root.command_applier, "command_applier NodePath")
	assert_eq(link.graph, root.graph, "graph NodePath")
	# OFF is what keeps offline play byte-for-byte unchanged: nothing is
	# serialized, nothing is sent. A role raises the mode; the mount never does.
	assert_eq(link.mode, CommandLink.Mode.OFF, "mounted idle")
	assert_true(root.command_applier.is_authority,
			"and an unlinked peer still decides for itself")


# --- the harness, which inherits the pair -----------------------------------

func test_the_harness_swaps_the_transport_instead_of_adding_one() -> void:
	# `instantiate()` without adding to the tree: this builds the node tree and
	# resolves exported NodePaths without running a 71-node sandbox's `_ready`.
	var root: Node = preload(MP_SANDBOX).instantiate()
	var found := _network_children(root)
	assert_eq(found["transport"], [TRANSPORT_PATH],
			"exactly one transport, at the inherited name — a second pair is the failure this test exists for")
	assert_eq(found["link"], [LINK_PATH], "exactly one link, at the inherited name")
	assert_true(root.get_node(TRANSPORT_PATH) is EnetTransport,
			"and the harness's is the ENet one, got %s" % root.get_node(TRANSPORT_PATH))
	root.free()


# --- the role the menu leaves behind ----------------------------------------

func test_a_host_role_raises_the_link_to_broadcast() -> void:
	GameSession.network = NetworkConfig.host()
	var root: GameRoot = await _live_game_root()
	assert_eq(root.command_link.mode, CommandLink.Mode.BROADCAST)
	assert_true(root.command_applier.is_authority, "a host decides")
	assert_eq(root.transport.role, NetworkTransport.Role.HOST, "and the socket was opened")


func test_a_client_role_makes_this_peer_a_mirror() -> void:
	GameSession.network = NetworkConfig.join("127.0.0.1")
	var root: GameRoot = await _live_game_root()
	assert_eq(root.command_link.mode, CommandLink.Mode.MIRROR)
	# The one consequence that has to be true BEFORE the level's first turn:
	# a client that thinks it decides has already diverged.
	assert_false(root.command_applier.is_authority, "a client is told")


func test_an_offline_role_is_the_same_as_no_role_at_all() -> void:
	GameSession.network = NetworkConfig.offline()
	var root: GameRoot = await _live_game_root()
	assert_eq(root.command_link.mode, CommandLink.Mode.OFF)
	assert_eq(root.transport.role, NetworkTransport.Role.OFFLINE, "no socket was opened")


func test_the_level_the_menu_routes_to_can_actually_reach_a_peer() -> void:
	# GameRoot brings up whatever transport a level mounted; a Loopback asked to
	# host announces itself and links to nobody. So the menu's destination has
	# to be the scene that swaps in the real one, or "Host" is a silent no-op.
	var root: Node = preload(FIRST_LEVEL).instantiate()
	var found := _network_children(root)
	assert_eq(found["transport"], [TRANSPORT_PATH], "still exactly one transport")
	assert_true(root.get_node(TRANSPORT_PATH) is EnetTransport,
			"and it is the ENet one, got %s" % root.get_node(TRANSPORT_PATH))
	root.free()


func test_the_harness_link_still_reaches_its_probe() -> void:
	# The one export the harness overrides on the INHERITED link (#529's probe
	# is dev-only and stays authored here). If the override stops resolving,
	# the probe measures nothing and says so nowhere.
	var root: Node = preload(MP_SANDBOX).instantiate()
	var link: CommandLink = root.get_node(LINK_PATH)
	assert_not_null(link.probe, "probe NodePath survives the inherited-node override")
	assert_eq(link.transport, root.get_node(TRANSPORT_PATH), "and it points at the swapped transport")
	root.free()
