extends GutTest

## #548 — the UPWARD channel. A client's [Command] does not apply locally: it
## goes up as a [constant CommandLink.KIND_INTENT], the host runs it through the
## same `_validate -> confirm -> apply` a local command takes, and the confirm
## comes back down as an ordinary [constant CommandLink.KIND_COMMAND] the client
## applies. A refusal rides its own [constant CommandLink.KIND_REFUSAL].
##
## [b]Two worlds in one process[/b] — the same fixture, and the same caveats, as
## `test/unit/network/test_command_link.gd`; read that file's docstring before
## adding anything here that kills an entity.
##
## [b]The loopback is synchronous.[/b] [method LoopbackTransport.send] emits on
## the peer inside the call, so a whole round trip completes inside the client's
## `submit()`. That is what makes the "still outstanding" assertions here unplug
## the transport (`peer = null`) instead of racing a frame: the only way to
## observe the open window is to make sure nothing answers.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _host: Dictionary
var _client: Dictionary
var _host_link: CommandLink
var _client_link: CommandLink
var _client_pic: PlayerInputController


func before_each() -> void:
	_host = await _build_world("host")
	_client = await _build_world("client")

	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])

	_host_link = _make_link(_host, pair[0], CommandLink.Mode.BROADCAST)
	_client_link = _make_link(_client, pair[1], CommandLink.Mode.MIRROR)

	_client_pic = PlayerInputController.new()
	_client_pic.graph = _client["graph"]
	_client_pic.allocation_system = _client["alloc"]
	_client_pic.turn_manager = _client["tm"]
	_client_pic.command_applier = _client["applier"]
	_client_pic.player = _client["player"]
	add_child_autofree(_client_pic)


func _make_link(world: Dictionary, transport: NetworkTransport, mode: CommandLink.Mode) -> CommandLink:
	var link := CommandLink.new()
	# Exports before `add_child`: `_ready` is what connects the signals.
	link.transport = transport
	link.command_applier = world["applier"]
	link.graph = world["graph"]
	link.mode = mode
	add_child_autofree(link)
	return link


## One self-contained world: graph, four nodes in a path, a player holding A.
## Lifted from `test_command_link.gd` — see there for why each world's entity
## has to bind its OWN [TurnManager] while the others are hidden from the group.
func _build_world(label: String) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)

	var nodes: Dictionary = {}
	for id in ["A", "B", "C", "D"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		graph.add_skill_node(sn)
		nodes[id] = sn
	graph.add_edge(nodes["A"], nodes["B"])
	graph.add_edge(nodes["B"], nodes["C"])
	graph.add_edge(nodes["C"], nodes["D"])

	var tm: TurnManager = autofree(TurnManager.new())
	tm.name = "TurnManager_%s" % label
	add_child(tm)

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	alloc.navigator = graph.navigator
	alloc.turn_manager = tm
	add_child_autofree(alloc)

	var player: Entity = autofree(Entity.new())
	player.display_name = "Player_%s" % label
	player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var hidden_managers: Array[Node] = []
	for other in get_tree().get_nodes_in_group(TurnManager.GROUP):
		if other != tm:
			hidden_managers.append(other)
			other.remove_from_group(TurnManager.GROUP)
	graph.entities_container.add_child(player)
	for other in hidden_managers:
		other.add_to_group(TurnManager.GROUP)

	await get_tree().process_frame

	player.core_location = nodes["A"]
	alloc.force_allocate(player, nodes["A"])
	tm.start_turn(player)
	player.stat_board.skill_points.grant(5)

	var applier := CommandApplier.new()
	applier.graph = graph
	applier.allocation_system = alloc
	applier.turn_manager = tm
	add_child_autofree(applier)

	return {
		"graph": graph, "alloc": alloc, "tm": tm,
		"applier": applier, "player": player, "nodes": nodes,
	}


func _id(world: Dictionary, key: String) -> int:
	return (world["graph"] as Graph).get_stable_id(world["nodes"][key])


func _applier(world: Dictionary) -> CommandApplier:
	return world["applier"] as CommandApplier


func _allocate(world: Dictionary, key: String) -> AllocateCommand:
	return AllocateCommand.new((world["player"] as Entity).entity_id, _id(world, key))


## Cut the client's outbound wire so an intent goes nowhere and the awaiting
## window stays observable. See the class docstring.
func _unplug_client() -> void:
	(_client_link.transport as LoopbackTransport).peer = null


# ── The round trip ────────────────────────────────────────────────────────────

func test_a_client_command_goes_up_and_lands_on_both_peers() -> void:
	_applier(_client).submit(_allocate(_client, "B"))
	await get_tree().process_frame

	assert_eq((_host["nodes"]["B"] as SkillNode).owned_by, _host["player"] as Entity,
			"the HOST is what decides — the intent must have reached its applier")
	assert_eq((_client["nodes"]["B"] as SkillNode).owned_by, _client["player"] as Entity,
			"and the confirm came back down and applied on the originator too")
	assert_eq(WorldFingerprint.compute(_client["graph"]), WorldFingerprint.compute(_host["graph"]),
			"worlds must agree after a client-initiated command")


func test_the_client_does_not_apply_its_own_command_locally() -> void:
	# No prediction (#548 decision 5). With nothing answering, the client's own
	# world must not have moved.
	_unplug_client()
	_applier(_client).submit(_allocate(_client, "B"))
	await get_tree().process_frame

	assert_null((_client["nodes"]["B"] as SkillNode).owned_by,
			"a peer that is TOLD applies nothing until it is told")
	assert_eq(_applier(_client).pending_count(), 0,
			"and it does not queue it either — the intent went up, not into the queue")


func test_the_intent_id_survives_the_host_round_trip_unchanged() -> void:
	# Mint-if-absent, never unconditional: the host puts a received intent
	# through the same `submit()`, so a blanket mint there would overwrite the
	# client's id, the confirm would echo the host's, and the client's gate
	# would never close.
	var confirmed_on_host: Array[int] = []
	_applier(_host).command_confirmed.connect(
			func(c: Command) -> void: confirmed_on_host.append(c.intent_id))

	var command := _allocate(_client, "B")
	_applier(_client).submit(command)
	var minted := command.intent_id
	await get_tree().process_frame

	assert_ne(minted, 0, "the submitting peer mints — 0 means unminted")
	assert_eq(confirmed_on_host, [minted] as Array[int],
			"the host echoes the client's id verbatim; it must never re-mint")


func test_a_host_minted_id_and_a_client_minted_id_cannot_collide() -> void:
	var host_command := _allocate(_host, "B")
	_applier(_host).submit(host_command)
	await get_tree().process_frame
	var client_command := _allocate(_client, "C")
	_applier(_client).submit(client_command)
	await get_tree().process_frame

	assert_ne(host_command.intent_id, client_command.intent_id,
			"the peer id owns the high half, so two peers' first intents differ")


# ── The awaiting gate ─────────────────────────────────────────────────────────

func test_the_client_cannot_act_while_a_confirmation_is_outstanding() -> void:
	# Acceptance 4. The guard itself already existed (#541,
	# `player_input_controller.gd`'s fourth gate); what was missing was anything
	# that could make the window wider than a stack frame.
	assert_true(_client_pic.can_player_act(),
			"fixture sanity: the client's player can act before it submits")

	_unplug_client()
	_applier(_client).submit(_allocate(_client, "B"))

	assert_true(_applier(_client).is_awaiting_confirmation,
			"the intent is out and undecided")
	assert_false(_client_pic.can_player_act(),
			"so the player must not be able to raise a second command")


func test_only_the_confirm_this_peer_SENT_closes_the_gate() -> void:
	# Acceptance 5, and the whole reason correlation is an id rather than
	# `entity_id`: a host-originated command carrying this entity's id would
	# otherwise unlock input one command early.
	_unplug_client()
	var sent := _allocate(_client, "B")
	_applier(_client).submit(sent)

	var unrelated := _allocate(_client, "C")
	unrelated.intent_id = sent.intent_id + 1000
	_applier(_client).apply_remote(unrelated)
	await get_tree().process_frame
	assert_true(_applier(_client).is_awaiting_confirmation,
			"a confirm for somebody else's intent must leave the window open")

	var unminted := _allocate(_client, "D")
	_applier(_client).apply_remote(unminted)
	await get_tree().process_frame
	assert_true(_applier(_client).is_awaiting_confirmation,
			"and so must a host-originated command, which carries no id this peer minted")

	var echo := _allocate(_client, "B")
	echo.intent_id = sent.intent_id
	_applier(_client).apply_remote(echo)
	await get_tree().process_frame
	assert_false(_applier(_client).is_awaiting_confirmation,
			"the peer's OWN confirm is what closes it")


# ── Refusal (acceptance 3 — the failure mode this must not ship) ──────────────

func test_a_refused_client_command_closes_the_gate_and_reports_it() -> void:
	# D is not adjacent to the player's only owned node, so the HOST's gate
	# refuses it. The client never validated anything, so without the refusal
	# leg it would wait forever.
	var outcomes: Array = []
	_applier(_client).command_applied.connect(
			func(c: Command, ok: bool) -> void: outcomes.append([c, ok]))

	var command := _allocate(_client, "D")
	_applier(_client).submit(command)
	await get_tree().process_frame

	assert_false(_applier(_client).is_awaiting_confirmation,
			"no hang: a refusal that arrived must close the window")
	assert_eq(outcomes.size(), 1, "exactly one outcome reported on the client")
	assert_eq(outcomes[0][0], command,
			"and it hands back the very command the player raised, which is what " \
			+ "PlayerInputController._on_command_applied renders")
	assert_false(outcomes[0][1], "reported as a failure, through the existing route")
	assert_true(_client_pic.can_player_act(),
			"and the player has their input back")


func test_a_refusal_names_a_code_not_a_ui_string() -> void:
	_applier(_client).submit(_allocate(_client, "D"))
	await get_tree().process_frame

	assert_eq(_applier(_client).last_refusal_reason, CommandLink.REASON_REFUSED,
			"the reason crosses as a StringName code; rendering it is a HUD question")


func test_a_successful_client_command_sends_no_refusal() -> void:
	var kinds: Array[String] = []
	(_client_link.transport as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: kinds.append(String(p.get(CommandLink.KEY_KIND, ""))))

	_applier(_client).submit(_allocate(_client, "B"))
	await get_tree().process_frame

	assert_eq(kinds, [CommandLink.KIND_COMMAND] as Array[String],
			"a confirmed command already closes the gate; a second message would be noise")


# ── #525's camera director hangs off `command_confirmed` ──────────────────────

func test_a_refusal_never_confirms_on_the_client() -> void:
	# Camera constraint 1. The director builds a FocusRequest and pans on
	# `command_confirmed`; a refusal that confirmed would pan to a node that
	# then did not change.
	var confirms: Array[Command] = []
	_applier(_client).command_confirmed.connect(
			func(c: Command) -> void: confirms.append(c))

	_applier(_client).submit(_allocate(_client, "D"))
	await get_tree().process_frame

	assert_true(confirms.is_empty(),
			"a refused command changed nothing and must never confirm anywhere")


func test_every_peer_that_applies_confirms_exactly_once() -> void:
	# Camera constraint 4, and the one most easily broken: if the confirm became
	# authority-only, a mirror peer's camera would go dead and the whole feature
	# would be host-only. Both directions are checked, because the client now
	# has two ways in — its own round-tripped intent, and a host-originated
	# command it is simply told about.
	var host_confirms: Array[StringName] = []
	var client_confirms: Array[StringName] = []
	_applier(_host).command_confirmed.connect(
			func(c: Command) -> void: host_confirms.append(c.type_tag()))
	_applier(_client).command_confirmed.connect(
			func(c: Command) -> void: client_confirms.append(c.type_tag()))

	_applier(_client).submit(_allocate(_client, "B"))
	await get_tree().process_frame
	assert_eq(client_confirms.size(), 1,
			"the ORIGINATING mirror peer confirms when the command lands on it")

	_applier(_host).submit(_allocate(_host, "C"))
	await get_tree().process_frame
	assert_eq(client_confirms.size(), 2,
			"and so does a mirror peer for a host-originated command")
	assert_eq(host_confirms.size(), 2,
			"once per command on the authority too — a double emit is a double pan")
