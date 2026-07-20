@tool
class_name ProcgenCard
extends PanelContainer
## A single procgen sample result card (#264) — extracted from
## [ProcgenPlaygroundPanel]'s repeated `_make_card` so both sub-tabs
## `instantiate()` this scene in a loop instead of hand-welding the
## frame/box pair per index.
##
## The card owns its own row population: [method fill] renders one budget
## roll (header + breakdown line + modifier rows); [method show_placeholder]
## renders a single dim message row instead — used before the first roll,
## and (by the panel's convention) only for card slot 0 of a cleared row.
## [member header_tint] is exposed so a themed variant can preview
## differently in the editor without touching the script.

@export var header_tint: Color = Color(0.85, 0.9, 1.0)

@onready var _box: VBoxContainer = %Box


## Clears every row without adding a placeholder.
func clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


## Clears, then adds a single dim placeholder row.
func show_placeholder(msg: String) -> void:
	clear()
	var l := Label.new()
	l.text = msg
	l.modulate = Color(1, 1, 1, 0.55)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)


## Renders one budget roll: header (index + budget), `breakdown_text`
## (already formatted by the caller — see
## [method ProcgenPlaygroundPanel._breakdown_text]) if non-empty, a
## separator, then one row per rolled [StatModifier] (or "(nothing)" if none
## rolled).
func fill(index: int, sample: Dictionary, breakdown_text: String) -> void:
	clear()
	var header := Label.new()
	header.text = "#%d · budget %d" % [index + 1, int(sample.get("budget", 0))]
	header.add_theme_font_size_override(&"font_size", 12)
	header.modulate = header_tint
	_box.add_child(header)
	if breakdown_text != "":
		var why := Label.new()
		why.text = breakdown_text
		why.add_theme_font_size_override(&"font_size", 10)
		why.modulate = Color(1, 1, 1, 0.55)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(why)
	_box.add_child(HSeparator.new())
	var mods: Array = sample.get("mods", [])
	if mods.is_empty():
		var empty := Label.new()
		empty.text = "(nothing)"
		empty.modulate = Color(1, 1, 1, 0.45)
		_box.add_child(empty)
		return
	for m in mods:
		var row := Label.new()
		row.text = "%s %s" % [String(m.stat_id), m.contribution_text()]
		row.add_theme_font_size_override(&"font_size", 11)
		_box.add_child(row)
