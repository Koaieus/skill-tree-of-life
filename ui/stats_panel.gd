@tool
class_name StatsPanel
extends VBoxContainer

## Read-only stats column. Set `board` (or rebind it) and the panel populates
## one row per visible stat per tab, refreshing on each stat's value_changed.
##
## What renders and in what order is driven entirely by StatDef metadata —
## `display_type` picks the widget (BASIC / PROGRESS, others reserved or
## HIDDEN) and `display_order` sorts the column. Adding a stat is a one-file
## change: drop a .tres in stats_system/defs/, set its order, type, and
## display_group, and the panel picks it up the next time the board is bound.
##
## Tabs group stats by StatDef.display_group. Anything with an empty or
## unrecognised display_group lands in the catch-all "···" tab (hidden when
## empty).

const _TAB_FALLBACK: StringName = &"misc"

# Tab order + display. Glyphs are unicode stopgaps; can swap to textures later.
const _TABS: Array[Dictionary] = [
	{ "id": &"body",   "title": "♥  Body"   },
	{ "id": &"combat", "title": "⚔  Combat" },
	{ "id": &"mind",   "title": "🧠 Mind"   },
	{ "id": &"sense",  "title": "👁 Sense"  },
	{ "id": _TAB_FALLBACK, "title": "···"   },
]

@export var board: StatBoard:
	set(value):
		_disconnect_board()
		board = value
		_connect_board()
		_rebuild()

# stat id → list of row Controls (one per tab the stat appears in — exactly
# 1 entry now that the "All" tab is gone). Refresh walks each.
var _rows: Dictionary[StringName, Array] = {}
var _tab_container: TabContainer = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_tab_container = null
	if board == null:
		return
	_tab_container = TabContainer.new()
	_tab_container.name = "Tabs"
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tab_container)

	var per_tab: Dictionary[StringName, VBoxContainer] = {}
	var known_ids: Array[StringName] = []
	for tab_def in _TABS:
		var tab_id: StringName = tab_def["id"]
		known_ids.append(tab_id)
		var vb := VBoxContainer.new()
		vb.name = tab_def["title"]
		_tab_container.add_child(vb)
		per_tab[tab_id] = vb

	var defs := _collect_visible_defs()
	defs.sort_custom(func(a, b): return a.display_order < b.display_order)
	for def in defs:
		var group: StringName = def.display_group
		var dest: StringName = group if group in known_ids else _TAB_FALLBACK
		_add_row_to_tab(def, per_tab[dest])
		_refresh(def.id)

	# Hide tabs with no rows — empty tabs are clutter.
	for tab_def in _TABS:
		var tab_id: StringName = tab_def["id"]
		var vb := per_tab[tab_id]
		if vb.get_child_count() == 0:
			vb.queue_free()


func _add_row_to_tab(def: StatDef, tab_vb: VBoxContainer) -> void:
	var row := _build_row(def)
	if row == null:
		return
	row.name = String(def.id)
	tab_vb.add_child(row)
	var bucket: Array = _rows.get(def.id, [])
	bucket.append(row)
	_rows[def.id] = bucket


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
	var rows: Array = _rows.get(id, [])
	if rows.is_empty() or board == null:
		return
	var stat := board.get_stat(id)
	if stat == null:
		return
	var def := stat.definition
	var stat_name: String = def.display_name if def != null else String(id)
	var tint: Color = def.tint_color if def != null else Color.WHITE
	for row in rows:
		if not is_instance_valid(row):
			continue
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
