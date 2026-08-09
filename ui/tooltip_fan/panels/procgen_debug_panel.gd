@tool
class_name ProcgenDebugPanel
extends FanPanel

## Tooltip V2 (#292) — DEVELOPER content: what procgen actually rolled for this
## node, read from the `procgen_footprint` meta `GraphProcgen` stamps in
## `graph_procgen.gd`. A live hover readout is worth keeping while procgen
## content is still being tuned; `DebugClipboard`'s `c` dump does NOT cover this
## meta (it dumps `role_tags` only), so this panel is its only home, not a nicer
## duplicate of an existing one.
##
## Deliberately held to a LOWER BAR than the content panels (#292 decisions):
##
## - It is not part of the crown scope gradient and gets no rung assignment.
##   Placement is out-of-the-way, not reviewed — it sits far left of everything
##   else in `fan.tscn` simply because that region is empty.
## - No [PanelHeader], no scanline overlay: every row is dim monospace-register
##   text under a `[procgen]` tag, so it reads as instrumentation rather than as
##   a readout a player is meant to parse.
## - Height is content-driven and unbounded. Nothing else derives from its
##   extent, so there is no authored envelope to respect.
##
## **It must stay cleanly removable.** One scene, deleted from `fan.tscn`, with
## nothing else to unpick: no shared component exists to serve it and no other
## panel reads from it. Assume it gets deleted — `procgen_footprint` is read
## here and nowhere else in `ui/`.

## Debug tone — deliberately the lowest-contrast text in the whole fan.
const _DIM := Color(0.45, 0.45, 0.5)
const _TAG_FONT_SIZE := 10
const _ROW_FONT_SIZE := 10

## Authored envelope, kept modest because the [PanelLayout] skin grows to
## whatever [method bind] produced. The structural overlap test measures this
## pre-bind rect, so it also has to be a footprint that genuinely fits where
## the unit is placed.
const _HALF_WIDTH := 80.0
const _H_PADDING := 8.0

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready — Label.text is a real serializable property,
	# so write no placeholder content during an editor load.
	if Engine.is_editor_hint():
		return


## Public entry point (#292). Rebuilds from scratch; a node without the meta
## renders nothing and [method has_content] then suppresses the whole unit.
## The skin's size follows whatever rows were rendered structurally — the
## Content column is a [PanelContent] and the [PanelLayout] skin hugs it
## (#344), so nothing here sizes anything.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild_rows()


## False whenever the node carries no `procgen_footprint` — hand-authored nodes
## (the dev sandbox, every test fixture) show no panel and no empty box.
func has_content() -> bool:
	return _bound_node != null and _bound_node.has_meta(&"procgen_footprint")


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not has_content():
		return
	_add_row("[procgen]", _TAG_FONT_SIZE)
	for line in _footprint_lines(_bound_node.get_meta(&"procgen_footprint")):
		_add_row(line, _ROW_FONT_SIZE)


## Substance parity with `skill_node_tooltip.gd::_populate_procgen_debug`, the
## V1 block #235 deleted: budget, the slot count with its primary/off split,
## the peak/off_cap pair when present, phase, and role tags.
func _footprint_lines(fp: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var phase: String = String(fp.get("phase", "?"))
	var budget: int = int(fp.get("budget", -1))
	if fp.has("slots"):
		var primary: int = int(fp.get("primary_slots", 0))
		var off: int = int(fp.get("off_slots", 0))
		lines.append("budget %d · slots %d (%dP+%dO)" % [budget, int(fp["slots"]), primary, off])
		if fp.has("peak_primary_cost"):
			lines.append("peak %d · off_cap %d" % [int(fp["peak_primary_cost"]), int(fp.get("off_cap", 0))])
	elif budget >= 0:
		lines.append("budget %d · phase %s" % [budget, phase])
	var role_tags: Array = fp.get("role_tags", [])
	if not role_tags.is_empty():
		lines.append("role: " + ", ".join(PackedStringArray(
			role_tags.map(func(t: Variant) -> String: return String(t)))))
	return lines


func _add_row(text: String, font_size: int) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.modulate = _DIM
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _HALF_WIDTH * 2.0 - _H_PADDING * 2.0
	_rows.add_child(label)
