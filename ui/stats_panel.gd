@tool
class_name StatsPanel
extends VBoxContainer

## Read-only stats column. Set `board` (or rebind it) and the panel populates
## one row per visible stat, refreshing on each stat's value_changed.
##
## What renders and in what order is driven entirely by StatDef metadata —
## `display_type` picks the widget (BASIC / PROGRESS, others reserved or
## HIDDEN) and `display_order` sorts the column. Adding a stat is a one-file
## change: drop a .tres in stats_system/defs/, set its order and type, and
## the panel picks it up the next time the board is bound.

@export var board: StatBoard:
	set(value):
		_disconnect_board()
		board = value
		_connect_board()
		_rebuild()

var _rows: Dictionary[StringName, Control] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	if board == null:
		return
	var defs := _collect_visible_defs()
	defs.sort_custom(func(a, b): return a.display_order < b.display_order)
	for def in defs:
		var row := _build_row(def)
		if row == null:
			continue
		row.name = String(def.id)
		add_child(row)
		_rows[def.id] = row
		_refresh(def.id)


func _collect_visible_defs() -> Array[StatDef]:
	var out: Array[StatDef] = []
	for def in StatRegistry.get_all_defs():
		if def.display_type == StatDef.DisplayType.HIDDEN:
			continue
		if board.get_stat(def.id) == null:
			continue
		out.append(def)
	return out


# --- Widget construction ----------------------------------------------------

func _build_row(def: StatDef) -> Control:
	match def.display_type:
		StatDef.DisplayType.PROGRESS:
			return LabeledProgressBar.create()
		_:
			# BAR and INLINE fall through to BASIC until their widgets are
			# implemented. Bumping a .tres to one of those won't break the
			# panel — just keeps the stat in the column as a label row.
			return _build_basic_row()


func _build_basic_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


# --- Refresh ----------------------------------------------------------------

func _refresh(id: StringName) -> void:
	var row: Control = _rows.get(id)
	if row == null or board == null:
		return
	var stat := board.get_stat(id)
	if stat == null:
		return
	var def := stat.definition
	var stat_name: String = def.display_name if def != null else String(id)
	var tint: Color = def.tint_color if def != null else Color.WHITE
	if row is LabeledProgressBar and stat is PoolStat:
		var pool := stat as PoolStat
		var cap := float(pool.value)
		var text := "%s: %d/%d" % [stat_name, int(pool.current), int(cap)]
		(row as LabeledProgressBar).set_values(text, float(pool.current), cap, tint)
	elif row is HBoxContainer:
		var name_label: Label = row.get_node_or_null("Name")
		var value_label: Label = row.get_node_or_null("Value")
		if name_label != null:
			name_label.text = stat_name
		if value_label != null:
			value_label.text = "%d" % int(stat.value)


# --- Signal wiring ----------------------------------------------------------

func _connect_board() -> void:
	if board == null:
		return
	for def in StatRegistry.get_all_defs():
		var stat := board.get_stat(def.id)
		if stat == null:
			continue
		var cb := _refresh.bind(def.id)
		if not stat.value_changed.is_connected(cb):
			stat.value_changed.connect(cb)
		# PoolStat.set_current emits value_changed alongside current_changed,
		# and modifier-driven cap changes also route through value_changed —
		# one connection covers both axes.


func _disconnect_board() -> void:
	# bind() returns a fresh Callable each call, so we can't compare to a
	# previously-bound one. Rebuilding the panel disconnects implicitly by
	# freeing the rows and clearing the dict — listeners are weakly held via
	# the stat → callable connection, but the stat outlives the panel. A
	# targeted disconnect lives here if it becomes a real leak.
	pass
