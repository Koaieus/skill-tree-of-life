@tool
class_name ModalBase
extends Control

## Scenic modal shell shared by every full-screen pick modal (LootPicker,
## SpellLootPicker — #486). Owns the Dim/Center/Panel/VBox chrome, the
## Title/Subtitle/ConfirmButton, and the modal lifecycle (present → freeze
## input → confirm → resolve → unfreeze → closed). Concrete modals are
## INHERITED SCENES of `modal_base.tscn` (restyle the border tint, title,
## confirm-button text) whose script `extends ModalBase` and calls
## [method present] with their own body scene + title.
##
## Content is a SWAPPABLE BODY (same shape as [CommandTrayBodyBase] —
## `%BodySlot` gets exactly one [ModalBodyBase] instance per present()) so
## LootPicker's stat-modifier cards and SpellLootPicker's spell cards don't
## have to duplicate the shell, freeze, or confirm-gating logic — only the
## card-building/selection details that actually differ.
##
## Freezes [PlayerInputController]'s input channels instead of
## `get_tree().paused` (#486) — pausing the whole tree would also stall
## confirmed-command RPC dispatch under the LAN sync model (see
## docs/domain/multiplayer-sync-model.md), and it's what let a Tween-driven
## AnnouncementLayer banner render on top of a frozen, dimmed modal.

signal closed()

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _confirm_button: Button = %ConfirmButton
@onready var _body_slot: Control = %BodySlot

var _input_ctl: PlayerInputController = null
var _body: ModalBodyBase = null
var _request: Variant = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	hide()
	_confirm_button.pressed.connect(_on_confirm)


func bind(input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl


## Swap in `body_scene`'s instance for `request`, set the title, and show —
## freezing the acting player's input channel for the duration of the pick.
## Concrete modals call this from their own `present(request)`.
func _present(body_scene: PackedScene, title_text: String, request: Variant) -> void:
	_request = request
	_title.text = title_text

	for child in _body_slot.get_children():
		child.queue_free()
	_body = body_scene.instantiate()
	_body_slot.add_child(_body)
	if not _body.selection_changed.is_connected(_on_body_selection_changed):
		_body.selection_changed.connect(_on_body_selection_changed)
	_body.populate(request)
	_on_body_selection_changed()

	show()
	if _input_ctl != null:
		_input_ctl.set_input_frozen(true)


func _on_body_selection_changed() -> void:
	if _body == null:
		return
	_confirm_button.disabled = not _body.is_selection_valid()
	_subtitle.text = _body.status_text()


func _on_confirm() -> void:
	if _body == null or not _body.is_selection_valid():
		return
	var chosen: Array = _body.resolve()
	var request: Variant = _request
	_request = null
	hide()
	if _input_ctl != null:
		_input_ctl.set_input_frozen(false)
	request.resolve(chosen)
	closed.emit()
