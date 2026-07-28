@tool
class_name AddonsPanel
extends FanPanel

## Tooltip V2 (#226/#229) — crown, NEAR rung (node-scoped), right by default.
## Capped at 3 items + a "+N more" tail (fixed envelope, unlike the two
## growing crown panels). Placeholder rows only — #229 replaces
## `_build_placeholder_rows` with real [AddonItem] bindings. Deliberately NOT
## instancing [AddonItem] here: #221 is mid-refactor on it in parallel
## (deleting `ModSlabRow.play_entry`), so a stub that only needs to prove
## size/placement stays decoupled with plain [Label]s.

const _CAP := 3

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	super._ready()
	_header.bind("Addons")
	_build_placeholder_rows()


func _build_placeholder_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in range(_CAP):
		var l := Label.new()
		l.text = "addon %d" % (i + 1)
		l.modulate = Color(0.85, 0.75, 0.95)
		_rows.add_child(l)
	var tail := Label.new()
	tail.text = "+N more"
	tail.modulate = Color(0.55, 0.55, 0.6)
	_rows.add_child(tail)
