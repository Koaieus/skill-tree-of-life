extends GutTest

## A link ending MID-RUN, which until now only the lobby handled (#716): the
## level connected `peer_joined` and `link_changed` and nothing else, so a peer
## that lost its host sat behind a permanently closed input gate with nothing
## on screen, and a host whose peer left sat on that peer's turn forever.
##
## Drives a real [GameRoot] (its own scene, so the transport it mounts is the
## shipping [LoopbackTransport] and the wiring is [method GameRoot._open_link]'s)
## as a HOST with one local hero and one remote human seat. The link events are
## raised on the mounted transport directly — what a socket does is the
## transport's contract, pinned in `test/unit/network/`; what the LEVEL does
## with the news is the seam under test here.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

const _HOST_PEER := 1
const _REMOTE_PEER := 2

var _root: GameRoot
var _local: Entity
var _remote: Entity
var _remote_seat: Participant
var _saved_ai_delay: float


func before_each() -> void:
	GameSession.end()
	# The AI paces its turn off this setting; a seat handed over mid-turn is
	# played out below, and the test should not wait on a real 0.4s beat.
	_saved_ai_delay = Settings.current.ai_turn_delay
	Settings.current.ai_turn_delay = 0.0
	GameSession.network = NetworkConfig.host()
	GameSession.local_peer_id = _HOST_PEER

	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	# `_open_link` sits past the last await in `_ready` — see
	# `test_link_mount.gd` for why fewer frames sees a level with no link.
	await wait_frames(6)

	var nodes: Array[SkillNode] = []
	for i in 4:
		var sn := _SKILL_NODE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 120, 0)
		_root.graph.add_skill_node(sn)
		nodes.append(sn)
	for i in 3:
		_root.graph.add_edge(nodes[i], nodes[i + 1])

	_local = _root.spawn_entity("Host", Color.CYAN, nodes[0], _BALANCED)
	_remote = _root.spawn_entity("Guest", Color.ORANGE, nodes[3], _BALANCED)

	var roster := ParticipantRoster.new()
	var host_seat := Participant.new()
	host_seat.id = 1
	host_seat.kind = Participant.Kind.HUMAN
	host_seat.camp = _CAMP_1
	host_seat.peer_id = _HOST_PEER
	roster.add(host_seat)
	_remote_seat = Participant.new()
	_remote_seat.id = 2
	_remote_seat.kind = Participant.Kind.HUMAN
	_remote_seat.camp = _CAMP_2
	_remote_seat.peer_id = _REMOTE_PEER
	roster.add(_remote_seat)
	GameSession.roster = roster
	GameRoot.apply_roster({1: _local, 2: _remote}, roster)
	_root._ensure_controllers()
	_root.bind_player(_local)
	await wait_frames(1)


func after_each() -> void:
	Settings.current.ai_turn_delay = _saved_ai_delay
	GameSession.end()


func _hand_turn_to(ent: Entity) -> void:
	var tm := _root.turn_manager
	if tm.current_entity != null:
		var prev := tm.current_entity
		tm.current_entity = null
		tm.turn_ended.emit(prev)
	tm.start_turn(ent)


# --- the fixture's own promises -------------------------------------------

func test_the_level_opened_its_link_as_host() -> void:
	assert_true(_root.transport.peer_left.is_connected(_root._on_peer_left),
			"peer_left reaches the level")
	assert_true(_root.transport.link_lost.is_connected(_root._on_link_lost),
			"link_lost reaches the level")
	assert_true(_remote.is_human_controlled)
	assert_true(GameRoot._find_controller(_remote) is PlayerController)


# --- host: a peer leaves --------------------------------------------------

func test_a_departed_peers_hero_is_handed_to_the_ai() -> void:
	_root.transport.peer_left.emit(_REMOTE_PEER)

	assert_false(_remote.is_human_controlled, "no longer a human's seat")
	assert_true(GameRoot._find_controller(_remote) is AIController,
			"an AIController drives it now")
	assert_eq(_remote_seat.kind, Participant.Kind.AI,
			"the roster agrees, so the loot registry stops parking its picks on a remote human")
	# The seat that stayed is untouched.
	assert_true(_local.is_human_controlled)
	assert_true(GameRoot._find_controller(_local) is PlayerController)


func test_a_peer_leaving_on_its_own_turn_does_not_strand_the_turn() -> void:
	_hand_turn_to(_remote)
	assert_eq(_root.turn_manager.current_entity, _remote)

	_root.transport.peer_left.emit(_REMOTE_PEER)
	# The new controller was kicked by hand; its turn is a coroutine that ends
	# through the applier like any AI turn.
	await wait_for_signal(_root.turn_manager.turn_ended, 3.0)

	assert_ne(_root.turn_manager.current_entity, _remote,
			"the AI ended the turn the human would never have")


func test_an_unknown_peer_leaving_changes_nothing() -> void:
	_root.transport.peer_left.emit(99)

	assert_true(_remote.is_human_controlled)
	assert_eq(_remote_seat.kind, Participant.Kind.HUMAN)


func test_a_client_leaves_a_sibling_peers_seat_alone() -> void:
	# A client hears `peer_left` for a sibling too; only the authority acts.
	GameSession.network = NetworkConfig.join("127.0.0.1")
	_root.transport.peer_left.emit(_REMOTE_PEER)

	assert_true(_remote.is_human_controlled)
	assert_eq(_remote_seat.kind, Participant.Kind.HUMAN)


# --- any peer: the link dies ----------------------------------------------

func test_a_lost_link_abandons_the_pending_intent() -> void:
	# A mirror parks its intent until the authority answers (#548).
	_root.command_applier.is_authority = false
	_hand_turn_to(_local)
	var cmd := EndTurnCommand.new()
	cmd.entity_id = _local.entity_id
	_root.command_applier.submit(cmd)
	assert_true(_root.command_applier.is_awaiting_confirmation, "precondition: parked")

	_root.transport.link_lost.emit("host went away")

	assert_false(_root.command_applier.is_awaiting_confirmation,
			"nobody is left to confirm it — the gate reopens")
	assert_eq(_root.command_applier.last_refusal_reason, &"link_lost")


func test_a_lost_link_presents_the_way_out() -> void:
	var overlay := _root.hud_root.run_end_overlay
	assert_false(overlay.visible, "precondition: no run end yet")

	_root.transport.link_lost.emit("host went away")

	assert_true(overlay.visible)
	assert_eq(overlay.reading, RunEndOverlay.Reading.LINK_LOST)
	assert_string_contains(overlay.subtitle_label.text, "host went away")


func test_a_link_lost_after_the_run_ended_leaves_the_verdict_up() -> void:
	# The host leaving for the menu is how every run ends for a client: its
	# `Wire.stop()` is this peer's `link_lost`, arriving over a verdict.
	var outcome := RunOutcome.new()
	outcome.winning_camp = _CAMP_2
	_root.victory_system.outcome = outcome
	_root.hud_root._on_run_ended(outcome)
	var overlay := _root.hud_root.run_end_overlay
	assert_true(overlay.visible, "precondition: the verdict is up")
	var verdict := overlay.reading
	assert_ne(verdict, RunEndOverlay.Reading.LINK_LOST)

	_root.transport.link_lost.emit("host went away")

	assert_eq(overlay.reading, verdict, "a normal end of run is not a lost connection")
	assert_true(overlay.visible)


# --- #755: the handover crosses the wire ----------------------------------

## Reading the layer's playing request straight off `_current_by_kind`, the way
## `test_run_end_presentation.gd` does — the layer emits nothing, and the point
## here is only "a banner for THIS was raised", not how it animates.
func _playing_main_text() -> String:
	var layer := _root.hud_root.announcement_layer
	var playing: AnnouncementRequest = layer._current_by_kind.get(
			AnnouncementRequest.Kind.TITLE)
	return "" if playing == null else playing.main_text


func test_the_host_announces_the_handover_and_broadcasts_it() -> void:
	var lines: Array[String] = []
	_root.command_link.logged.connect(func(line: String) -> void: lines.append(line))

	_root.transport.peer_left.emit(_REMOTE_PEER)

	assert_string_contains(_playing_main_text(), "Guest",
			"the host's own screen names who left")
	var sent := lines.filter(func(l: String) -> bool: return l.begins_with("→ seat 2"))
	assert_eq(sent.size(), 1, "and the mirrors are told exactly once")


## The regression that matters: a mirror applies the SHARED half only. An
## [AIController] here would be a second machine deciding actions for a hero it
## has no authority over.
func test_a_mirror_applies_the_handover_without_growing_a_controller() -> void:
	GameSession.network = NetworkConfig.join("127.0.0.1")
	_root.command_link.mode = CommandLink.Mode.MIRROR

	_root.command_link.seat_handover_received.emit(2)

	assert_eq(_remote_seat.kind, Participant.Kind.AI, "the mirror's roster agrees")
	assert_false(_remote.is_human_controlled,
			"so SeatPolicy.vision_group stops revealing through it, as it has on the host")
	assert_true(GameRoot._find_controller(_remote) is PlayerController,
			"the inert controller is left alone — a mirror never drives a hero")
	assert_string_contains(_playing_main_text(), "Guest",
			"and this peer is told why its ally started playing differently")


func test_a_handover_for_a_seat_this_peer_does_not_know_is_ignored() -> void:
	_root.command_link.mode = CommandLink.Mode.MIRROR

	_root.command_link.seat_handover_received.emit(99)

	assert_eq(_remote_seat.kind, Participant.Kind.HUMAN)
	assert_true(_remote.is_human_controlled)
