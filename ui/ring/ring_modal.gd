@tool
class_name RingModal
extends ModalBase
## The inner-ring modal: presents a [RingBody] for `{entity, table}` and emits
## [signal ModalBase.confirmed] with `[cell_name]` per buy. [HudRoot] raises it
## through its modal queue and turns each confirm into a
## [SpendRingCellCommand].
##
## [b]Confirm does not close.[/b] Unlike every other [ModalBase], a buy leaves
## the modal up: the body marks the cell pending and re-populates on the
## entity's `ring_changed`, so a player with points left keeps buying, and at
## zero it stays open read-only (confirm dead). Only Later / Esc / right-click
## closes it — the base's cancel path, which is also the one `closed` emits on.
##
## A refused buy reaches the body through the bound input controller's
## [CommandApplier]: `command_applied(cmd, false)` is the one route a refusal
## takes on every peer — the authority's own validate-fail and a host's
## [method CommandApplier.refuse_intent] alike.

const _BODY_SCENE := preload("res://ui/ring/ring_body.tscn")


func present(entity: Entity, table: RingTable) -> void:
	_watch_refusals()
	_present(_BODY_SCENE, "INNER RING", {"entity": entity, "table": table})


## The presented body; null before the first [method present].
func body() -> RingBody:
	return _body as RingBody


func _on_confirm() -> void:
	if _body == null or not _body.is_selection_valid():
		return
	var chosen: Array = _body.resolve()
	body().mark_pending(chosen[0])
	confirmed.emit(chosen, _request)


## Connected on present rather than in [method ModalBase.bind]: the controller's
## applier is a scene-wired export, and present is the first moment it matters.
## The applier is level-lifetime, so this connects once and never disconnects.
func _watch_refusals() -> void:
	if _input_ctl == null or _input_ctl.command_applier == null:
		return
	var applier := _input_ctl.command_applier
	if not applier.command_applied.is_connected(_on_command_applied):
		applier.command_applied.connect(_on_command_applied)


func _on_command_applied(command: Command, success: bool) -> void:
	var spend := command as SpendRingCellCommand
	if success or spend == null or body() == null:
		return
	body().refuse(spend.entity_id, spend.cell)
