@tool
class_name OwnerPanel
extends FanPanel

## Tooltip V2 (#226/#228) — crown, FAR rung (entity-scoped). Fixed-height
## authored attribute list per #228's spec (an explicit list, not a
## radar/enumeration of the whole board — see the #269 CON-hexagon catch on
## #226's mount-contract comment). Placeholder rows only; #228 replaces
## `_build_placeholder_rows` with the real bind().

## The authored attribute set — fixed by construction, never grown by a stat
## landing on the board later. Placeholder labels only; #228 swaps these for
## real StatValueRow bindings.
const _ATTRIBUTES := ["Strength", "Dexterity", "Intelligence", "Wisdom", "Perception"]

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	super._ready()
	# `_header.bind()` writes into an OWNED node's `Label.text` (a real,
	# serializable property) — per `.claude/rules/godot-workflow.md`'s @tool
	# _ready guard convention, skip all placeholder content in the editor.
	# The panel's size envelope comes from the authored HoloPanel/Content
	# rects, not from row count or header text, so nothing is lost for
	# in-editor placement/preview.
	if Engine.is_editor_hint():
		return
	_header.bind("Owner")
	_build_placeholder_rows()


func _build_placeholder_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for a in _ATTRIBUTES:
		var l := Label.new()
		l.text = a + "  —"
		l.modulate = Color(0.85, 0.88, 0.95)
		_rows.add_child(l)
