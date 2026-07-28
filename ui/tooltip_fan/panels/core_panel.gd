@tool
class_name CorePanel
extends FanPanel

## Tooltip V2 (#226/#231) — crown, FAR rung (entity-scoped), CORE nodes only
## (`owned_core.tscn`). Envelope sized to the worst case per the "Crown
## envelope inputs" issue comment: 8 modifier leaves (`pacifist_core.tres`) +
## 1 core-HP row = 9, with headroom to 12 rows. Deliberate gold skin
## exception (#231) — everything else in the fan defaults to hologram.

const _ENVELOPE_ROWS := 12

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	super._ready()
	_header.bind("Core")
	_build_placeholder_rows()


func _build_placeholder_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in range(_ENVELOPE_ROWS):
		var l := Label.new()
		l.text = "core mod %d" % (i + 1)
		l.modulate = Color(0.95, 0.85, 0.55)
		_rows.add_child(l)
