@tool
class_name NodeStatsPanel
extends FanPanel

## Tooltip V2 (#226/#230) — crown, NEAR rung (node-scoped), left by default.
## Envelope sized to the worst case per the "Crown envelope inputs" comment:
## 2 always-shown rows + local/aura stats, 8 rows of headroom.

const _ENVELOPE_ROWS := 8

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	super._ready()
	_header.bind("Node Stats")
	_build_placeholder_rows()


func _build_placeholder_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in range(_ENVELOPE_ROWS):
		var l := Label.new()
		l.text = "stat %d" % (i + 1)
		l.modulate = Color(0.7, 0.9, 0.8)
		_rows.add_child(l)
