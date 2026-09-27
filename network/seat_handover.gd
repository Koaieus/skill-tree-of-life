class_name SeatHandover
extends Node
## "This seat is the AI's now" — the one flow that turns a human's seat over to
## the AI, host and mirror alike (#755). Composed beside [NetworkSession] in
## `game_root.tscn`; it listens to the session's two seat signals and emits
## [signal seat_handed_over] for the level's presentation (seat vision, the
## banner). It lives in `network/` rather than with [SeatPolicy] because a peer
## REPRODUCES what it does — the roster flip and the entity flag — while
## SeatPolicy never feeds anything a peer reproduces.
##
## Host: [signal NetworkSession.peer_left] → every HUMAN seat of that peer →
## [method hand_seat_to_ai]. Mirror: [signal NetworkSession.seat_handover] →
## the shared half only ([method _adopt]).

## A seat passed to the AI on this peer. [param quiet] is [member quiet]: the
## handover was asked for (autoplay), so nobody left and nothing is announced.
signal seat_handed_over(entity: Entity, quiet: bool)

@export var network_session: NetworkSession
@export var command_link: CommandLink
@export var turn_manager: TurnManager
@export var controller_factory: ControllerFactory
## Set when the handovers are asked for rather than forced (#754) — `--autoplay`
## hands every seat over on purpose; a HUD crying that somebody left would be
## the harness lying about the very run it is checking. Rides the signal
## rather than being passed down, because the mirror's entry is told a seat
## changed hands and never why — and both processes are configured alike.
@export var quiet := false


func _ready() -> void:
	if network_session == null:
		return
	network_session.peer_left.connect(_on_seat_vacated)
	network_session.seat_handover.connect(_on_seat_handover)


## The HOST's half of "this seat is the AI's now" — the authority-only parts,
## on top of the [method _adopt] every peer runs.
##
## The broadcast (#755) goes out BEFORE the turn kick, and that order is
## load-bearing: the wire is reliable-ordered, so sequencing the handover ahead
## of the AI's first command is what stops a mirror seeing an AI act on a seat
## it still believes a human holds.
##
## The entity half swaps the no-op [PlayerController] for an [AIController].
## If it is this hero's turn RIGHT NOW the new controller missed
## `turn_started`, and the human who would have ended the turn is gone — so the
## turn is kicked by hand. Fire-and-forget, as [signal Entity.turn_began]
## calls it. This half is the host's ALONE: a mirror that grew an
## [AIController] of its own would be a second machine deciding actions for a
## hero it has no authority over, which is the whole of
## `.claude/rules/multiplayer-sync.md` broken in one line.
func hand_seat_to_ai(participant: Participant) -> void:
	var ent := _adopt(participant)
	if command_link != null:
		command_link.send_seat_handover(participant.id)
	if ent == null:
		return
	var ai := controller_factory.replace_with_ai(ent)
	if turn_manager.current_entity == ent:
		ai.take_turn()


## The [Entity] seated for [param participant_id], or null (0 names no seat).
func entity_for_participant(participant_id: int) -> Entity:
	if participant_id == 0:
		return null
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var ent := node as Entity
		if ent != null and ent.participant_id == participant_id:
			return ent
	return null


## Host-side: a seated peer left mid-run. Every HUMAN seat it held goes to the
## AI ([method hand_seat_to_ai]) so the run goes on for everyone still here.
func _on_seat_vacated(peer_id: int) -> void:
	if GameSession.roster == null:
		return
	for p in GameSession.roster.all():
		if p.kind == Participant.Kind.HUMAN and p.peer_id == peer_id:
			hand_seat_to_ai(p)


## Mirror-side entry for the same handover, off
## [signal CommandLink.seat_handover_received] (#755). Applies the shared half
## and nothing else — see [method hand_seat_to_ai] for why the controller swap
## must not follow it here.
func _on_seat_handover(participant_id: int) -> void:
	if GameSession.roster == null:
		return
	var participant := GameSession.roster.by_id(participant_id)
	if participant == null:
		return
	_adopt(participant)


## What EVERY peer does when a seat passes to the AI, host and mirror alike.
## Returns the seat's [Entity], or null if this peer has none for it.
##
## [b]The roster half comes first[/b], and matters beyond the controller:
## [method LootPickRegistry.is_remote_collector] reads [member Participant.kind],
## and a HUMAN seat whose peer is gone would park every relic this hero claims
## on a pick that never comes (#646) — a second hang behind the first.
##
## [b]The flag half is why this crosses the wire at all[/b] (#755). Until then
## the host flipped [member Entity.is_human_controlled] alone and every mirror's
## copy stayed `true` — but [method SeatPolicy.vision_group] is an ALLIED-HUMANS
## reveal keyed on exactly that flag, so a coop ally on a third machine went on
## seeing through a hero the host had already stopped sharing with. Fog is
## local-view-only, so this was never a desync of the authoritative world; it
## was two machines drawing different maps of it. That group is COMPUTED, not
## reactive, so the level's [signal seat_handed_over] handler re-derives seat
## vision explicitly.
func _adopt(participant: Participant) -> Entity:
	participant.kind = Participant.Kind.AI
	var ent := entity_for_participant(participant.id)
	if ent == null:
		return null
	ent.is_human_controlled = false
	seat_handed_over.emit(ent, quiet)
	return ent
