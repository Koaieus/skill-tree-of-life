class_name SaveGate
extends Node

signal saved(error: Error)
signal save_held_changed(held: bool)

@export var command_applier: CommandApplier
@export var graph: Graph
@export var slot_path: String = SaveFile.SLOT_PATH

const REASON_ONLINE := ""
const REASON_LOOT := ""

var is_save_held: bool = false


func can_save() -> bool:
	return false


func blocked_reason() -> String:
	return ""


func request_save() -> bool:
	return false
