@tool
class_name ModalBase
extends Control

## Scenic modal shell shared by every full-screen modal (LootPicker,
## SpellLootPicker, MassActionConfirmPanel — #486). Owns the
## Dim/Center/Panel/VBox chrome, the Title/Subtitle/Confirm/Cancel buttons, and
## the modal lifecycle (present → freeze input → confirm-or-cancel → unfreeze →
## closed). Concrete modals are INHERITED SCENES of `modal_base.tscn` (restyle
## the border tint, title, button text) whose script `extends ModalBase` and
## calls [method _present] with their own body scene + title.
##
## Content is a SWAPPABLE BODY (same shape as [CommandTrayBodyBase] —
## `%BodySlot` gets exactly one [ModalBodyBase] instance per `_present()`) so a
## modal only authors the part that actually differs: loot's stat-modifier
## cards, the spell draft's spell cards, the mass-action confirm's per-node
## breakdown. The shell, the freeze and the confirm-gating are the base's.
##
## [b]The base never resolves anything.[/b] It emits [signal confirmed] /
## [signal cancelled] carrying the request it was presented with, and the
## concrete modal decides what that means — a [LootPickRequest] resolves
## itself, a [MassActionRequest] routes back through [PlayerInputController].
## There is deliberately no duck-typed `request.resolve()` call here: the two
## request families have genuinely different handshakes.
##
## Freezes [PlayerInputController]'s input channels instead of
## `get_tree().paused` (#486) — pausing the whole tree would also stall
## confirmed-command RPC dispatch under the LAN sync model (see
## docs/domain/multiplayer-sync-model.md), and it's what let a Tween-driven
## AnnouncementLayer banner render on top of a frozen, dimmed modal.
##
## See docs/domain/modal-system.md.

## Confirm pressed with a valid selection. `chosen` is the body's
## [method ModalBodyBase.resolve] (empty for a modal with nothing to select);
## `request` is whatever was handed to [method _present].
signal confirmed(chosen: Array, request: Variant)
## Cancel / Esc / right-click on a [member cancellable] modal. The request was
## refused — nothing was applied.
signal cancelled(request: Variant)
## The modal is down, whatever the exit. Always fires exactly once per
## `_present`, AFTER [signal confirmed]/[signal cancelled] — that ordering is
## what lets a modal raised BY the confirmed action queue behind this one.
signal closed()

## Can the player walk away? A loot pick is a must-answer (there is no "no
## relic"); a mass-action confirm is a yes/no, so it shows the Cancel button
## and honours Esc / right-click. Set per inherited scene.
@export var cancellable: bool = false:
	set(value):
		cancellable = value
		if _cancel_button != null:
			_cancel_button.visible = value

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _body_slot: Control = %BodySlot

var _input_ctl: PlayerInputController = null
var _body: ModalBodyBase = null
var _request: Variant = null


func _ready() -> void:
	_cancel_button.visible = cancellable
	if Engine.is_editor_hint():
		return
	hide()
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(_on_cancel)


func bind(input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl


## Swap in `body_scene`'s instance for `request`, set the title, and show —
## freezing the acting player's input channel for the duration. Concrete
## modals call this from their own `present(request)`.
func _present(body_scene: PackedScene, title_text: String, request: Variant) -> void:
	_request = request
	_title.text = title_text

	for child in _body_slot.get_children():
		child.queue_free()
	_body = body_scene.instantiate()
	_body_slot.add_child(_body)
	if not _body.selection_changed.is_connected(_on_body_selection_changed):
		_body.selection_changed.connect(_on_body_selection_changed)
	_configure_body(_body)
	_body.populate(request)
	_on_body_selection_changed()

	show()
	if _input_ctl != null:
		_input_ctl.set_input_frozen(true)


## Hand the fresh body whatever it needs beyond the request itself, between
## `instantiate()` and [method ModalBodyBase.populate]. Default no-op — most
## bodies read everything off the request.
func _configure_body(_body_instance: ModalBodyBase) -> void:
	pass


## Take the modal down WITHOUT resolving it — the decision was made or revoked
## elsewhere (e.g. `PlayerInputController.clear_transient_state` dropped the
## pending request on level teardown). Still unfreezes and still emits
## [signal closed], so input never latches frozen and the modal queue drains.
## No-op when not showing.
func dismiss() -> void:
	if not visible:
		return
	_close()
	closed.emit()


func _on_body_selection_changed() -> void:
	if _body == null:
		return
	_confirm_button.disabled = not _body.is_selection_valid()
	_subtitle.text = _body.status_text()
	var label := _body.confirm_text()
	if label != "":
		_confirm_button.text = label


func _on_confirm() -> void:
	if _body == null or not _body.is_selection_valid():
		return
	var chosen: Array = _body.resolve()
	# Down and unfrozen BEFORE the action runs, so anything the action raises
	# (a loot pick off a confirmed cascade) sees a clean modal surface.
	var request: Variant = _close()
	confirmed.emit(chosen, request)
	closed.emit()


func _on_cancel() -> void:
	if not cancellable or not visible:
		return
	var request: Variant = _close()
	cancelled.emit(request)
	closed.emit()


func _close() -> Variant:
	var request: Variant = _request
	_request = null
	hide()
	if _input_ctl != null:
		_input_ctl.set_input_frozen(false)
	return request


## Esc and right-click are the same "back out" gesture the armed-mode stack
## uses. Safe to own here: while a modal is up [PlayerInputController] is
## frozen and [PauseMenu] is blocked (HudRoot), so nothing else is listening.
##
## [b]`_input`, not `_unhandled_input`[/b] — the full-screen `Dim` is a
## `MOUSE_FILTER_STOP` ColorRect (it has to be: it's what keeps the HUD's own
## buttons from being clicked through a modal), so a mouse button is consumed
## as GUI input and never reaches the unhandled phase at all. Right-click would
## silently do nothing. Keys aren't GUI-picked, so Esc worked either way; both
## live here so there is one gesture handler, not two.
func _input(event: InputEvent) -> void:
	if not visible or not cancellable:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel()
		get_viewport().set_input_as_handled()
