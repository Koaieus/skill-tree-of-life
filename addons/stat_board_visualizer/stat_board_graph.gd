## Renders a StatBoard as a GraphEdit.
##
## - One `GraphNode` per stat, grouped into three `GraphFrame` columns
##   (Attributes · Pools · Derived).
## - One edge per intrinsic formula-driven modifier from its input stats to its
##   target — the *dependency*. The actual *contribution* (formula text +
##   effective value + op-tag) is rendered as a row inside the target node,
##   because that's where the number lives.
## - A toolbar (inside `GraphEdit.get_menu_hbox()`) lets the user append a
##   new intrinsic modifier without leaving the visualizer. Disk-backed
##   boards are written back via `ResourceSaver`; runtime boards mutate in
##   memory only.
##
## Refresh strategy: a 4 Hz timer drives `refresh()` for value updates;
## `_board.changed` triggers a full `_rebuild()` so inspector edits
## (modifier add/remove, retargeting, formula tweaks) propagate live.
##
## Scene shape — see `stat_board_graph.tscn`:
##   GraphEdit (this script)
##     ├─ RefreshTimer  (4 Hz; drives refresh)
##     └─ AddDialog     (instance of add_modifier_dialog.tscn)
##
## Instantiated by:
##   - `plugin.gd` (editor bottom panel + InspectorPlugin button)
##   - `ui/stat_board_overlay/` (runtime F3 toggle)
##
## In editor mode, stat values reflect base + manually-applied modifiers; the
## board's `apply_intrinsics()` has NOT been called, so the breakdown rows
## still show what *would* contribute once the board is wired to an entity.
@tool
extends GraphEdit

const _GROUP_LAYOUT := [
	{
		"title": "Attributes",
		"x": 40.0,
		"tint": Color(0.55, 0.30, 0.30, 0.35),
		"stats": [&"strength", &"dexterity", &"intelligence", &"wisdom", &"perception"],
	},
	{
		"title": "Pools",
		"x": 360.0,
		"tint": Color(0.30, 0.45, 0.55, 0.35),
		"stats": [
			&"health", &"mana", &"xp", &"skill_points",
			&"action_points", &"deallocation_points", &"movement_points",
		],
	},
	{
		"title": "Derived",
		"x": 680.0,
		"tint": Color(0.45, 0.40, 0.25, 0.35),
		"stats": [
			&"vision_range", &"sensor_range", &"node_health",
			&"xp_per_turn", &"mana_per_turn", &"initiative_speed",
		],
	},
]

# Per-op styling. Indexed by `StatModifier.Operation`.
const _OP_TAGS := ["+base", "+%", "×", "+bonus", "=set"]
const _OP_COLORS := [
	Color(0.62, 0.82, 1.00),  # ADD_BASE
	Color(0.95, 0.78, 0.42),  # INCREASE
	Color(0.95, 0.55, 0.55),  # MULTIPLY
	Color(0.65, 0.95, 0.70),  # ADD_BONUS
	Color(0.95, 0.55, 0.95),  # SET
]

const _ROW_H := 130.0
const _ROW_Y0 := 60.0
const _NODE_W := 280.0

@onready var _refresh_timer: Timer = %RefreshTimer
@onready var _add_dialog: ConfirmationDialog = %AddDialog

var _board: StatBoard = null
# id → { node:GraphNode, val_lbl:Label, base_lbl:Label, mod_lbl:Label,
#        breakdown:VBoxContainer, breakdown_rows:Array }
var _entries: Dictionary = {}
# Stats currently subscribed to `value_changed`. Tracked so we can disconnect cleanly.
var _connected_stats: Array[Stat] = []

# Toolbar widgets — appended to `get_menu_hbox()` at runtime.
var _board_label: Label
var _add_btn: Button


func _ready() -> void:
	_build_toolbar()
	_refresh_timer.timeout.connect(refresh)
	_add_dialog.modifier_confirmed.connect(_on_modifier_confirmed)
	# Drag-from-port-to-port → don't draw the visual link; instead pop the
	# add-modifier dialog prefilled with a Linear from→to. The actual edge
	# materialises when the user confirms (rebuild iterates intrinsic_modifiers).
	connection_request.connect(_on_connection_request)


func _exit_tree() -> void:
	_disconnect_board()


# --- Public ---------------------------------------------------------------

func load_board(board: StatBoard) -> void:
	if _board == board:
		_rebuild()
		return
	_disconnect_board()
	_board = board
	if _board != null and not _board.changed.is_connected(_on_board_changed):
		_board.changed.connect(_on_board_changed)
	_rebuild()


## Cheap per-tick value update. Called by the refresh timer; does NOT
## re-create nodes — use `_rebuild()` (or trigger `_board.changed`) for
## structural changes.
func refresh() -> void:
	if _board == null:
		return
	for id in _entries:
		var stat: Stat = _board.get_stat(id)
		if stat == null:
			continue
		var e: Dictionary = _entries[id]
		e.val_lbl.text = _value_text(stat)
		e.base_lbl.text = _base_text(stat)
		e.mod_lbl.text = _op_summary(stat)
	_refresh_breakdown_contributions()


# --- Toolbar --------------------------------------------------------------

func _build_toolbar() -> void:
	var bar := get_menu_hbox()
	bar.add_child(VSeparator.new())

	_board_label = Label.new()
	_board_label.text = "(no board)"
	_board_label.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.85))
	bar.add_child(_board_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	bar.add_child(spacer)

	_add_btn = Button.new()
	_add_btn.text = "+ Intrinsic Modifier"
	_add_btn.tooltip_text = "Append a new entry to the board's intrinsic_modifiers array"
	_add_btn.disabled = true
	_add_btn.pressed.connect(_on_add_pressed)
	bar.add_child(_add_btn)

	var rebuild_btn := Button.new()
	rebuild_btn.text = "↻"
	rebuild_btn.tooltip_text = "Rebuild the graph"
	rebuild_btn.pressed.connect(_rebuild)
	bar.add_child(rebuild_btn)


# --- Rebuild + node creation ---------------------------------------------

func _rebuild() -> void:
	_refresh_timer.stop()
	clear_connections()
	_disconnect_stats()

	var to_free: Array = []
	for child in get_children():
		if child is GraphElement:  # GraphNode + GraphFrame
			to_free.append(child)
	for c in to_free:
		remove_child(c)
		c.free()
	_entries.clear()

	_board_label.text = _board_display_name()
	_add_btn.disabled = _board == null
	if _board == null:
		return

	# 1. Frames first — attach_graph_element_to_frame requires the frame to exist.
	var frames: Array[GraphFrame] = []
	for col in _GROUP_LAYOUT.size():
		var spec: Dictionary = _GROUP_LAYOUT[col]
		var fr := GraphFrame.new()
		fr.title = spec.title
		fr.name = "frame_%s" % str(spec.title).to_lower()
		fr.tint_color = spec.tint
		fr.tint_color_enabled = true
		fr.autoshrink_enabled = true
		fr.autoshrink_margin = 24
		fr.position_offset = Vector2(spec.x, 16)
		add_child(fr)
		frames.append(fr)

	# 2. Stat nodes, attached to their frame.
	for col in _GROUP_LAYOUT.size():
		var spec: Dictionary = _GROUP_LAYOUT[col]
		var row := 0
		for id in spec.stats:
			var stat: Stat = _board.get_stat(id)
			if stat == null:
				continue
			var gn := _make_node(id, stat, col)
			gn.position_offset = Vector2(float(spec.x) + 24.0, _ROW_Y0 + row * _ROW_H)
			add_child(gn)
			attach_graph_element_to_frame(gn.name, frames[col].name)
			_subscribe_stat(stat)
			row += 1

	# 3. Edges + breakdown rows after one frame so slot rects are valid.
	await get_tree().process_frame
	_wire_edges_and_breakdowns()
	_refresh_timer.start()


func _make_node(id: StringName, stat: Stat, group_idx: int) -> GraphNode:
	var gn := GraphNode.new()
	gn.name = str(id)
	gn.title = _display_title(id, stat)
	gn.custom_minimum_size = Vector2(_NODE_W, 0)
	gn.resizable = false

	# Tint the title bar so the column is visually distinct even when frames overlap.
	var sb_title := StyleBoxFlat.new()
	sb_title.bg_color = _GROUP_LAYOUT[group_idx].tint
	sb_title.border_color = _GROUP_LAYOUT[group_idx].tint.darkened(0.2)
	sb_title.set_border_width_all(1)
	sb_title.content_margin_left = 8
	sb_title.content_margin_right = 8
	sb_title.content_margin_top = 4
	sb_title.content_margin_bottom = 4
	gn.add_theme_stylebox_override(&"titlebar", sb_title)

	# Slot 0: value row — left input, right output.
	var val_row := HBoxContainer.new()
	val_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gn.add_child(val_row)
	var val_lbl := Label.new()
	val_lbl.text = _value_text(stat)
	val_lbl.add_theme_font_size_override(&"font_size", 18)
	val_lbl.add_theme_color_override(&"font_color", Color(1, 1, 1))
	val_row.add_child(val_lbl)

	var base_lbl := Label.new()
	base_lbl.text = _base_text(stat)
	base_lbl.add_theme_font_size_override(&"font_size", 10)
	base_lbl.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.7))
	gn.add_child(base_lbl)

	var mod_lbl := Label.new()
	mod_lbl.text = _op_summary(stat)
	mod_lbl.add_theme_font_size_override(&"font_size", 10)
	mod_lbl.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.5))
	gn.add_child(mod_lbl)

	var breakdown := VBoxContainer.new()
	breakdown.add_theme_constant_override(&"separation", 1)
	gn.add_child(breakdown)

	gn.set_slot(
		0,
		true, 0, Color(0.55, 0.75, 1.0),
		true, 0, Color(0.55, 0.75, 1.0)
	)

	_entries[id] = {
		"node": gn,
		"val_lbl": val_lbl,
		"base_lbl": base_lbl,
		"mod_lbl": mod_lbl,
		"breakdown": breakdown,
		"breakdown_rows": [],
	}
	return gn


# --- Edges + breakdown rows ---------------------------------------------

func _wire_edges_and_breakdowns() -> void:
	if _board == null:
		return
	for m in _board.intrinsic_modifiers:
		if m == null:
			continue
		var to_id := StringName(m.stat_id)
		if not _entries.has(to_id):
			continue
		_add_breakdown_row(to_id, m)
		if m.formula == null:
			continue
		for src_id in m.formula.get_input_ids():
			if _entries.has(src_id):
				connect_node(src_id, 0, to_id, 0)


func _add_breakdown_row(target_id: StringName, m: StatModifier) -> void:
	var entry: Dictionary = _entries[target_id]
	var box: VBoxContainer = entry.breakdown

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)

	var op_lbl := Label.new()
	op_lbl.text = "[%s]" % _OP_TAGS[m.operation]
	op_lbl.add_theme_color_override(&"font_color", _OP_COLORS[m.operation])
	op_lbl.add_theme_font_size_override(&"font_size", 10)
	op_lbl.custom_minimum_size = Vector2(46, 0)
	row.add_child(op_lbl)

	var formula_lbl := Label.new()
	formula_lbl.text = _formula_text(m)
	formula_lbl.add_theme_font_size_override(&"font_size", 10)
	formula_lbl.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.85))
	formula_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formula_lbl.clip_text = true
	row.add_child(formula_lbl)

	var contrib_lbl := Label.new()
	contrib_lbl.text = _contribution_text(m)
	contrib_lbl.add_theme_font_size_override(&"font_size", 10)
	contrib_lbl.add_theme_color_override(&"font_color", _OP_COLORS[m.operation])
	row.add_child(contrib_lbl)

	box.add_child(row)
	entry.breakdown_rows.append({"modifier": m, "contrib_lbl": contrib_lbl})


func _refresh_breakdown_contributions() -> void:
	# Re-compute formula contributions for every breakdown row. Derived
	# modifiers can shift when their source stats change.
	for id in _entries:
		var entry: Dictionary = _entries[id]
		for r in entry.breakdown_rows:
			r.contrib_lbl.text = _contribution_text(r.modifier)


# --- Signal wiring -------------------------------------------------------

func _subscribe_stat(stat: Stat) -> void:
	if not stat.value_changed.is_connected(_on_stat_changed):
		stat.value_changed.connect(_on_stat_changed)
		_connected_stats.append(stat)


func _disconnect_stats() -> void:
	for s in _connected_stats:
		if is_instance_valid(s) and s.value_changed.is_connected(_on_stat_changed):
			s.value_changed.disconnect(_on_stat_changed)
	_connected_stats.clear()


func _disconnect_board() -> void:
	_disconnect_stats()
	if _board != null and _board.changed.is_connected(_on_board_changed):
		_board.changed.disconnect(_on_board_changed)


func _on_stat_changed() -> void:
	# Cheap: just refresh visible values. Structural changes route through
	# _on_board_changed (intrinsic_modifiers edited) and trigger _rebuild.
	refresh()


func _on_board_changed() -> void:
	# The .tres edited via inspector — intrinsic list, stat refs, etc.
	# Defer so we don't rebuild mid-property-set.
	call_deferred("_rebuild")


# --- Formatting helpers --------------------------------------------------

func _display_title(id: StringName, stat: Stat) -> String:
	if stat != null and stat.definition != null and stat.definition.display_name != "":
		return stat.definition.display_name
	return str(id)


func _value_text(stat: Stat) -> String:
	if stat is PoolStat:
		var ps := stat as PoolStat
		return "%s / %s" % [str(ps.current), str(ps.get_value())]
	return str(stat.get_value())


func _base_text(stat: Stat) -> String:
	return "base %s" % _trim_float(stat.base_value)


func _op_summary(stat: Stat) -> String:
	if stat._modifiers.size() == 0:
		return "—"
	var counts := [0, 0, 0, 0, 0]
	for m in stat._modifiers:
		counts[m.operation] += 1
	var parts: Array[String] = []
	for i in counts.size():
		if counts[i] > 0:
			parts.append("%s×%d" % [_OP_TAGS[i], counts[i]])
	return " · ".join(parts)


func _formula_text(m: StatModifier) -> String:
	if m.formula == null:
		return "const %s" % _trim_float(m.value)
	if m.formula is LinearFormula:
		var lf := m.formula as LinearFormula
		return "%s × %s" % [str(lf.source_stat_id), _trim_float(m.value)]
	if m.formula is ExpressionFormula:
		var ef := m.formula as ExpressionFormula
		return "%s × (%s)" % [_trim_float(m.value), ef.formula] if m.value != 1.0 else ef.formula
	return "<formula>"


## NOTE (#305): can't delegate to [method StatModifier.format] here — this
## editor tool previews disk-backed [StatBoard] resources that were never
## `add_modifier()`'d into a live board, so `m`'s own binding
## (`get_effective_value`'s `_board`) is null even though the visualizer's
## own `_board` (this panel's loaded resource) is the correct formula source.
## This stays a local effective-value computation against `_board`, not the
## modifier's; the row shows the bare contribution value ("= 5"), not a
## sentence — the stat name is already the node's own title.
func _contribution_text(m: StatModifier) -> String:
	return "= %s" % _trim_float(_contribution_value(m))


func _contribution_value(m: StatModifier) -> float:
	if m.formula != null and _board != null:
		return m.value * m.formula.compute(_board)
	return m.value


func _trim_float(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.2f" % v


func _board_display_name() -> String:
	if _board == null:
		return "(no board)"
	if _board.resource_path != "":
		return _board.resource_path.get_file()
	return "(unsaved board)"


# --- Add Intrinsic Modifier dialog --------------------------------------

func _on_add_pressed() -> void:
	if _board == null:
		return
	_add_dialog.call(&"populate", _collect_stat_ids())
	_add_dialog.popup_centered()


func _on_connection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	if _board == null:
		return
	if from_node == to_node:
		return
	_add_dialog.call(&"populate", _collect_stat_ids())
	_add_dialog.call(&"preset_linear", from_node, to_node)
	_add_dialog.popup_centered()


func _collect_stat_ids() -> Array:
	var ids: Array = []
	for spec in _GROUP_LAYOUT:
		for id in spec.stats:
			if _board.get_stat(id) != null:
				ids.append(id)
	return ids


func _on_modifier_confirmed(mod: StatModifier) -> void:
	if _board == null or mod == null:
		return
	# Append to the typed array via a copy so the property's "set" sees a
	# distinct value (some Godot versions skip change notifications on
	# in-place mutation of an exported array).
	var new_arr: Array[StatModifier] = _board.intrinsic_modifiers.duplicate()
	new_arr.append(mod)
	_board.intrinsic_modifiers = new_arr
	_board.emit_changed()  # triggers _on_board_changed → rebuild

	# Persist disk-backed boards in the editor; runtime boards live in memory.
	if _board.resource_path != "" and Engine.is_editor_hint():
		ResourceSaver.save(_board, _board.resource_path)
