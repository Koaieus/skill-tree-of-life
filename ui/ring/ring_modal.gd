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

const _BODY_SCENE := preload("res://ui/ring/ring_body.tscn")


func present(entity: Entity, table: RingTable) -> void:
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
