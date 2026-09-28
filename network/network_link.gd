class_name NetworkLink
extends Node

const KIND_REFUSED := "refused"

signal logged(line: String)

@export var transport: NetworkTransport
@export var channels: Array[LinkChannel] = []

var role: NetworkConfig.Role = NetworkConfig.Role.OFFLINE
var defer_until_world: bool = false
var _refused: bool = false


func register(_channel: LinkChannel) -> void:
	pass


func _on_message_received(_payload: Dictionary) -> void:
	pass
