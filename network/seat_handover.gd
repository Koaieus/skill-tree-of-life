class_name SeatHandover
extends Node

signal seat_handed_over(entity: Entity, quiet: bool)

@export var network_session: NetworkSession
@export var command_link: CommandLink
@export var turn_manager: TurnManager
@export var controller_factory: ControllerFactory
@export var quiet := false


func hand_seat_to_ai(_participant: Participant) -> void:
	pass


func entity_for_participant(_participant_id: int) -> Entity:
	return null
