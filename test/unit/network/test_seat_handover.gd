extends GutTest
## SeatHandover against its own collaborators only — a bare TurnManager,
## ControllerFactory and two entities, no GameRoot: the host's handover swaps
## the controller and kicks a turn in progress; the mirror's flips the same two
## facts and grows no AI of its own; `quiet` rides the signal.

const _BOARD := preload("res://entity/default_entity_board.tres")


## Counts kicks instead of deciding a turn.
class ProbeAI extends AIController:
	var kicks := 0

	func take_turn() -> void:
		kicks += 1


## Builds [ProbeAI]s so a kicked turn is observable.
class ProbeFactory extends ControllerFactory:
	func make_ai(_ent: Entity) -> AIController:
		var ai := ProbeAI.new()
		ai.name = "AIController"
		return ai


var _saved_roster: ParticipantRoster
var _seat: Participant
var _human: Entity
var _other: Entity
var _tm: TurnManager
var _session: NetworkSession
var _factory: ControllerFactory
var _handover: SeatHandover


func before_each() -> void:
	_saved_roster = GameSession.roster
	var roster := ParticipantRoster.new()
	_seat = Participant.new()
	_seat.id = 1
	_seat.kind = Participant.Kind.HUMAN
	_seat.peer_id = 2
	roster.add(_seat)
	GameSession.roster = roster
	_human = _make_entity("Human", 1, true)
	_other = _make_entity("Other", 0, true)
	_tm = TurnManager.new()
	autofree(_tm)
	_session = NetworkSession.new()
	autofree(_session)
	_factory = ProbeFactory.new()
	add_child_autofree(_factory)
	_factory.ensure_all()
	_handover = SeatHandover.new()
	_handover.network_session = _session
	_handover.turn_manager = _tm
	_handover.controller_factory = _factory
	add_child_autofree(_handover)
	watch_signals(_handover)


func after_each() -> void:
	GameSession.roster = _saved_roster


func _make_entity(ent_name: String, participant_id: int, human: bool) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.participant_id = participant_id
	e.is_human_controlled = human
	add_child_autofree(e)
	return e


func test_the_host_handover_flips_the_seat_and_swaps_in_an_ai() -> void:
	assert_true(ControllerFactory.find(_human) is PlayerController, "arranged: a human's controller")
	_handover.hand_seat_to_ai(_seat)

	assert_eq(_seat.kind, Participant.Kind.AI, "the roster says AI")
	assert_false(_human.is_human_controlled, "the entity says AI")
	assert_true(ControllerFactory.find(_human) is AIController, "an AIController drives it now")
	assert_signal_emit_count(_handover, "seat_handed_over", 1)
	var ai := ControllerFactory.find(_human) as ProbeAI
	assert_eq(ai.kicks if ai != null else -1, 0, "not its turn: nothing kicked")
	assert_true(ControllerFactory.find(_other) is PlayerController, "the other seat is untouched")


func test_the_mirror_entry_flips_the_facts_and_grows_no_ai() -> void:
	_session.seat_handover.emit(_seat.id)

	assert_eq(_seat.kind, Participant.Kind.AI, "the roster says AI")
	assert_false(_human.is_human_controlled, "the entity says AI")
	assert_true(ControllerFactory.find(_human) is PlayerController,
			"a mirror never grows an AIController for a hero it has no authority over")
	assert_signal_emit_count(_handover, "seat_handed_over", 1)


func test_a_handover_mid_turn_kicks_the_new_ai() -> void:
	_tm.adopt_turn(_human, 0)
	_handover.hand_seat_to_ai(_seat)

	var ai := ControllerFactory.find(_human) as ProbeAI
	assert_not_null(ai, "a probe AI is attached")
	assert_eq(ai.kicks if ai != null else -1, 1, "the turn in progress is kicked once")


func test_quiet_rides_the_signal() -> void:
	_handover.quiet = true
	_handover.hand_seat_to_ai(_seat)

	assert_signal_emitted_with_parameters(_handover, "seat_handed_over", [_human, true])
