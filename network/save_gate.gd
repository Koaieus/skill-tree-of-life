class_name SaveGate
extends Node
## Whether — and when — the running level may be written to the save slot.
## Offline only; otherwise SAVE is always pressable, whoever holds the turn.
## A request made while [method CommandApplier.is_quiescent] is false is HELD
## and taken at the next quiescent boundary, so a half-replayed
## [AttackRecord] is never captured. The world is captured when the save
## fires, never when it was requested. See docs/domain/save-load.md.

## Emitted when a requested save is written — at once, or when a held one fires.
signal saved(error: Error)
## [member is_save_held] transitioned — the HUD's "saving after this…" cue.
signal save_held_changed(held: bool)

const REASON_ONLINE := "No saving in an online run"
## The one held wait that is on a human, so the tooltip names it.
const REASON_LOOT := "Pick your loot first"

@export var command_applier: CommandApplier
@export var graph: Graph
@export var slot_path: String = SaveFile.SLOT_PATH

var is_save_held: bool = false


func _ready() -> void:
	command_applier.applying_changed.connect(_on_applier_settled.unbind(1))
	command_applier.awaiting_confirmation_changed.connect(_on_applier_settled.unbind(1))
	command_applier.outstanding_loot_changed.connect(_on_applier_settled.unbind(1))


## Is SAVE pressable? False only in an online run; a not-quiescent applier
## defers the save rather than refusing it.
func can_save() -> bool:
	return not _is_online()


## The tooltip: why SAVE is refused, or why a save would wait on the player.
## Empty when a press saves at once or after a reveal finishes.
func blocked_reason() -> String:
	if _is_online():
		return REASON_ONLINE
	if command_applier.has_outstanding_loot():
		return REASON_LOOT
	return ""


## Saves now when quiescent, else holds the request for the next quiescent
## boundary. False only when refused (online); a repeat press while held is a
## no-op that still answers true.
func request_save() -> bool:
	if not can_save():
		return false
	if command_applier.is_quiescent():
		_write()
	else:
		_set_held(true)
	return true


func _on_applier_settled() -> void:
	# Each flag clears before its signal fires, so the read here is current.
	if is_save_held and command_applier.is_quiescent():
		_set_held(false)
		if can_save():
			_write()


func _write() -> void:
	saved.emit(SaveFile.capture(graph).write_slot(slot_path))


func _set_held(held: bool) -> void:
	if held == is_save_held:
		return
	is_save_held = held
	save_held_changed.emit(held)


func _is_online() -> bool:
	var net: NetworkConfig = GameSession.network
	return net != null and net.is_online()
