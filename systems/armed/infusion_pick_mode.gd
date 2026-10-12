class_name InfusionPickMode
extends ArmedMode

var magic: MagicMode
var socket: int = 0


func _init(p_magic: MagicMode, p_socket: int) -> void:
	magic = p_magic
	ctl = p_magic.ctl
	socket = p_socket


func pick(_id: StringName) -> void:
	pass
