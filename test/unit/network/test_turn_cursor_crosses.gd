extends GutTest

## #756 — the mirror never starts a turn on its own.
##
## Every peer used to open its own first turn on its own seated hero
## ([method GameRoot._ready]'s `auto_start_turn` block), so the host opened on
## Player 1 and the client opened on Player 2. Nothing corrected it: the turn
## cursor is a host DECISION and neither leg of the sync model carried it. Every
## later [EndTurnCommand] then reproduced [method TurnManager._tick_until_ready]
## from a different starting cursor, turn-start upkeep ran for the wrong entity
## on the wrong turn, and the ACCUMULATED fingerprint tier drifted apart while
## ownership and topology stayed identical — exactly the shape rung 4 measured.
##
## Two doors onto the cursor, so two halves here: [StartTurnCommand] (the run's
## opening, command-ordered like every other handoff) and the resync
## ([method EntitySnapshot.restore_turn_cursor], for a peer whose world was
## encoded after the host had already started).

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


# --- fixtures ---------------------------------------------------------------

## A hand-built line of nodes with pinned stable ids, so the two worlds below
## address the same nodes by the same numbers.
func _line_graph(label: String, count: int) -> Graph:
	var graph: Graph = autofree(_GRAPH_SCENE.instantiate())
	graph.name = "Graph_%s" % label
	add_child(graph)
	await get_tree().process_frame
	var previous: SkillNode = null
	for i in count:
		var node: SkillNode = _NODE_SCENE.instantiate()
		node.position = Vector2(i * 100.0, 0.0)
		graph.add_skill_node(node)
		graph.restore_stable_id(node, i + 1)
		if previous != null:
			graph.add_edge(previous, node)
		previous = node
	return graph


func _new_entity(graph: Graph, display_name: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = display_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


## A whole peer: graph, two heroes on their own cores, an
## [AllocationSystem], a [TurnManager] and a [CommandApplier]. Deliberately NOT
## started — opening the turn is what these tests are about.
func _build_world(label: String) -> Dictionary:
	var graph := await _line_graph(label, 4)

	var tm: TurnManager = autofree(TurnManager.new())
	tm.name = "TurnManager_%s" % label
	add_child(tm)

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	alloc.navigator = graph.navigator
	alloc.turn_manager = tm
	add_child_autofree(alloc)

	var p1 := _new_entity(graph, "P1_%s" % label)
	var p2 := _new_entity(graph, "P2_%s" % label)
	await get_tree().process_frame

	var nodes := graph.get_skill_nodes()
	p1.core_location = nodes[0]
	alloc.force_allocate(p1, nodes[0])
	p2.core_location = nodes[3]
	alloc.force_allocate(p2, nodes[3])

	var applier := CommandApplier.new()
	applier.graph = graph
	applier.allocation_system = alloc
	applier.turn_manager = tm
	add_child_autofree(applier)

	return {"graph": graph, "tm": tm, "applier": applier, "p1": p1, "p2": p2, "alloc": alloc}


func _make_link(world: Dictionary, transport: NetworkTransport,
		mode: CommandLink.Mode) -> CommandLink:
	var link := CommandLink.new()
	link.transport = transport
	link.command_applier = world["applier"]
	link.graph = world["graph"]
	link.turn_manager = world["tm"]
	link.mode = mode
	add_child_autofree(link)
	return link


# --- 1. the command ---------------------------------------------------------

func test_it_round_trips_through_the_codec() -> void:
	var command := StartTurnCommand.new(7)
	var decoded := CommandCodec.from_dict(command.to_dict())
	assert_true(decoded is StartTurnCommand,
			"the codec must know the tag, or a mirror silently drops the opening cursor")
	assert_eq(decoded.entity_id, 7, "the actor IS the payload")
	assert_eq(decoded.type_tag(), StartTurnCommand.TAG)


func test_the_wire_form_carries_no_fingerprint() -> void:
	# `test/fixtures/outcome/*.tres` IS a serialized command dictionary — see
	# [member Command.pre_fingerprint]. `host_fingerprint` joined it as transient
	# applier state and must stay out of `to_dict` for the same reason.
	var command := StartTurnCommand.new(3)
	command.pre_fingerprint = 111
	command.host_fingerprint = 222
	var d := command.to_dict()
	assert_false(d.has("pre_fingerprint"), "pre_fingerprint is transient, not a wire field")
	assert_false(d.has("host_fingerprint"), "host_fingerprint is transient, not a wire field")


func test_it_opens_the_turn_and_fills_the_actors_clock() -> void:
	var world := await _build_world("solo")
	var tm: TurnManager = world["tm"]
	var p1: Entity = world["p1"]
	p1.stat_board.initiative.current = 0.0

	(world["applier"] as CommandApplier).submit(StartTurnCommand.new(p1.entity_id))
	await get_tree().process_frame

	assert_eq(tm.current_entity, p1, "the command is what opens the run's clock")
	assert_eq(tm.turns_taken, 1)
	# The clock was FILLED — `restore_to_full` moved out of `GameRoot._ready` and
	# into the command so it lands at the same point of the stream on every peer.
	# It reads 0 again afterwards on purpose: `initiative` is a
	# [CyclicPoolStatDef], so reaching its cap deducts the cycle and carries the
	# overshoot forward. What the fill actually buys is READINESS, and
	# [method TurnManager.start_turn] consuming it is the observable.
	assert_false(p1.is_in_group(Entity.READY_GROUP),
			"the actor's readiness is consumed by the turn it just opened")


func test_a_second_start_turn_is_refused() -> void:
	var world := await _build_world("solo")
	var tm: TurnManager = world["tm"]
	var applier: CommandApplier = world["applier"]
	var p1: Entity = world["p1"]
	var p2: Entity = world["p2"]

	applier.submit(StartTurnCommand.new(p1.entity_id))
	await get_tree().process_frame

	var refused_turns := tm.turns_taken
	applier.submit(StartTurnCommand.new(p2.entity_id))
	await get_tree().process_frame

	assert_eq(tm.current_entity, p1, "a mid-run start_turn is a duplicate, not a handoff")
	assert_eq(tm.turns_taken, refused_turns, "and it must not tally a turn either")


# --- 2. the loopback regression --------------------------------------------

## The bug itself: the host opens on ITS P1 and the mirror must end up on ITS
## OWN P1 — not on the hero this machine happens to seat.
func test_the_host_opening_turn_reaches_the_mirrors_own_p1() -> void:
	var host := await _build_world("host")
	var client := await _build_world("client")
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_make_link(host, pair[0], CommandLink.Mode.BROADCAST)
	_make_link(client, pair[1], CommandLink.Mode.MIRROR)

	assert_null((client["tm"] as TurnManager).current_entity,
			"sanity: a mirror holds no cursor of its own before the host speaks")

	(host["applier"] as CommandApplier).submit(
			StartTurnCommand.new((host["p1"] as Entity).entity_id))
	await get_tree().process_frame

	assert_eq((host["tm"] as TurnManager).current_entity, host["p1"], "sanity: the host opened")
	assert_eq((client["tm"] as TurnManager).current_entity, client["p1"],
			"the mirror's clock opens on ITS OWN P1, received from the host — "
			+ "opening on this machine's seated hero is #756")


## And it stays in step: two end_turns off the same starting cursor leave both
## TurnManagers with the same tally. Before #756 the two `_tick_until_ready`s
## started from different cursors and never re-converged, and the tally is the
## reported half of that — [member RunOutcome.turn_count] is exactly this
## number, and host 48 / client 38 for the same run was #756's second symptom.
##
## [b]It deliberately does not assert WHICH entity ends up holding the turn.[/b]
## Two worlds share one [SceneTree] here, and both
## [method TurnManager._tick_until_ready] and [method TurnManager.tick] read
## `Entity.GROUP` / `Entity.READY_GROUP` off that tree — so each peer's clock
## replenishes the OTHER peer's entities too and their initiative values are
## fixture noise. The opening cursor (the test above) is not affected: it is
## named outright by the command. Asserting identity after a handoff needs two
## trees, which is `mise run mp:e2e`'s job and is where #756 was actually found.
func test_the_cursor_stays_in_step_across_end_turns() -> void:
	var host := await _build_world("host")
	var client := await _build_world("client")
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_make_link(host, pair[0], CommandLink.Mode.BROADCAST)
	_make_link(client, pair[1], CommandLink.Mode.MIRROR)

	var host_tm: TurnManager = host["tm"]
	var client_tm: TurnManager = client["tm"]
	var applier: CommandApplier = host["applier"]

	applier.submit(StartTurnCommand.new((host["p1"] as Entity).entity_id))
	await get_tree().process_frame
	for _i in 2:
		applier.submit(EndTurnCommand.new(host_tm.current_entity.entity_id))
		await get_tree().process_frame

	assert_eq(host_tm.turns_taken, 3, "sanity: the opening plus two handoffs")
	assert_eq(client_tm.turns_taken, host_tm.turns_taken,
			"RunOutcome.turn_count reads this — host 48 / client 38 was #756's second symptom")


# --- 3. the resync half -----------------------------------------------------

## A peer whose world arrives AFTER the host has already started cannot receive
## the [StartTurnCommand] — it was sent before this peer had a socket. The
## cursor rides inside the snapshot instead.
func test_the_snapshot_carries_the_turn_cursor() -> void:
	var source := await _build_world("src")
	var target := await _build_world("dst")
	var src_tm: TurnManager = source["tm"]
	var dst_tm: TurnManager = target["tm"]

	src_tm.start_turn(source["p1"])
	src_tm.end_turn()
	assert_gt(src_tm.turns_taken, 1, "sanity: the source has a history to carry")

	var bytes := EntitySnapshot.encode(source["graph"])
	EntitySnapshot.decode(bytes, target["graph"])
	EntitySnapshot.resolve_graph_refs(bytes, target["graph"])
	EntitySnapshot.restore_turn_cursor(bytes, target["graph"], dst_tm)

	assert_eq(dst_tm.turns_taken, src_tm.turns_taken, "the level's tally is adopted outright")
	assert_eq((dst_tm.current_entity as Entity).entity_id,
			(src_tm.current_entity as Entity).entity_id,
			"and so is WHO holds the turn — a cursor a mirror invents for itself is #756")


## [member Entity.turns_taken] gates the first-turn upkeep skip, so a decoded
## entity reading 0 would re-grant that skip on the next turn it served and
## silently skip a turn of income the authority took.
func test_the_snapshot_carries_each_entitys_turn_tally() -> void:
	var source := await _build_world("src")
	var target := await _build_world("dst")
	var src_p1: Entity = source["p1"]
	src_p1.turns_taken = 5

	var bytes := EntitySnapshot.encode(source["graph"])
	EntitySnapshot.decode(bytes, target["graph"])

	assert_eq((target["p1"] as Entity).turns_taken, 5,
			"turns_taken crosses since #756 — a snapshotted peer heard none of "
			+ "the turn_started emits that produced it")


## [method TurnManager.adopt_turn] must not run the upkeep the payload already
## holds. The whole point of adopting rather than starting.
func test_adopting_a_cursor_runs_no_upkeep() -> void:
	var world := await _build_world("solo")
	var tm: TurnManager = world["tm"]
	var p1: Entity = world["p1"]
	p1.turns_taken = 4
	var xp_before: float = p1.stat_board.xp.current

	tm.adopt_turn(p1, 9)

	assert_eq(tm.current_entity, p1, "the cursor IS adopted")
	assert_eq(tm.turns_taken, 9)
	assert_eq(p1.turns_taken, 4, "adopting is not a turn served — the snapshot already counted it")
	assert_eq(p1.stat_board.xp.current, xp_before,
			"per-turn upkeep must not re-run: the board that arrived already holds its result")
	assert_false(tm.is_adopting, "the flag is scoped to the emit and nothing wider")


func test_adopting_the_cursor_it_already_holds_is_a_no_op() -> void:
	var world := await _build_world("solo")
	var tm: TurnManager = world["tm"]
	var p1: Entity = world["p1"]
	var started: Array[Entity] = []
	tm.turn_started.connect(func(e: Entity) -> void: started.append(e))

	tm.adopt_turn(p1, 3)
	tm.adopt_turn(p1, 3)

	assert_eq(started.size(), 1,
			"a mid-run repair whose cursor already agrees must be silent — every "
			+ "other step of a resync decode is idempotent too")


# --- 4. the owner mirrors ---------------------------------------------------

## [method GraphSnapshot._decode_node] writes `owned_by` directly, which is the
## write [EntityNavigator]'s mutation contract says will drift the mirror. The
## drift is silent and cumulative: [method Entity._on_turn_started] runs the D-9
## regen sweep over `navigator.get_mirrored_nodes()`, so an unmirrored node
## never heals on that peer while it heals on the authority.
func test_a_decoded_world_repairs_its_owner_mirrors() -> void:
	var source := await _build_world("src")
	var target := await _build_world("dst")
	var src_alloc: AllocationSystem = source["alloc"]
	var src_p1: Entity = source["p1"]
	src_alloc.force_allocate(src_p1, (source["graph"] as Graph).get_skill_nodes()[1])

	var entity_bytes := EntitySnapshot.encode(source["graph"])
	var graph_bytes := GraphSnapshot.encode(source["graph"])
	EntitySnapshot.decode(entity_bytes, target["graph"])
	GraphSnapshot.decode(graph_bytes, target["graph"])
	EntitySnapshot.resolve_graph_refs(entity_bytes, target["graph"])

	var dst_p1: Entity = target["p1"]
	assert_eq(dst_p1.navigator.get_mirrored_nodes().size(),
			src_p1.navigator.get_mirrored_nodes().size(),
			"the decoded peer's owned-subgraph mirror must hold what it now owns — "
			+ "a node it never mirrored simply never regens there (#756)")
