@tool
class_name StatsPanel
extends VBoxContainer

## Read-only stats column. Set `board` (or rebind it) and the panel populates
## one row per visible stat per tab, refreshing on each stat's value_changed.
##
## What renders and in what order is driven entirely by StatDef metadata —
## `display_type` picks the widget (BASIC / PROGRESS, others reserved or
## HIDDEN) and `display_order` sorts the column. Adding a stat is a one-file
## change: drop a .tres in stats_system/defs/, set its order and type, and
## the panel picks it up the next time the board is bound.
##
## Tabs (per #32) group stats by category. Category comes from the optional
## in-script `_CATEGORY` map (stat id → category name); anything unmapped
## lands in the catch-all "Misc" tab. "All" mirrors the flat layout.

const _TAB_ALL: StringName = &"all"
const _TAB_OVERVIEW: StringName = &"overview"
const _TAB_COMBAT: StringName = &"combat"
const _TAB_MAGIC: StringName = &"magic"
const _TAB_DEFENSE: StringName = &"defense"
const _TAB_POOLS: StringName = &"pools"
const _TAB_MISC: StringName = &"misc"

const _TAB_TITLES: Dictionary[StringName, String] = {
	_TAB_OVERVIEW: "Overview",
	_TAB_COMBAT: "Combat",
	_TAB_MAGIC: "Magic",
	_TAB_DEFENSE: "Defense",
	_TAB_POOLS: "Pools",
	_TAB_MISC: "Misc",
	_TAB_ALL: "All",
}

# Stat-id → category. Anything not listed falls into _TAB_MISC. Update here
# when adding a new stat — kept in-script so .tres files don't sprout an
# extra field. Promote to `StatDef.category` if the map grows unwieldy.
const _CATEGORY: Dictionary[StringName, StringName] = {
	&"strength": _TAB_OVERVIEW,
	&"dexterity": _TAB_OVERVIEW,
	&"intelligence": _TAB_OVERVIEW,
	&"wisdom": _TAB_OVERVIEW,
	&"perception": _TAB_OVERVIEW,
	&"initiative_speed": _TAB_OVERVIEW,
	&"xp_per_turn": _TAB_OVERVIEW,
	&"vision_range": _TAB_OVERVIEW,
	&"sensor_range": _TAB_OVERVIEW,

	&"action_points": _TAB_COMBAT,
	&"blade_size": _TAB_COMBAT,
	&"range": _TAB_COMBAT,

	&"mana": _TAB_MAGIC,
	&"mana_per_turn": _TAB_MAGIC,
	&"spell_range": _TAB_MAGIC,

	&"health": _TAB_DEFENSE,
	&"node_health": _TAB_DEFENSE,
	&"armor": _TAB_DEFENSE,
	&"min_damage_taken": _TAB_DEFENSE,
	&"wound_heal_per_turn": _TAB_DEFENSE,

	&"xp": _TAB_POOLS,
	&"skill_points": _TAB_POOLS,
	&"deallocation_points": _TAB_POOLS,
	&"movement_points": _TAB_POOLS,
}

# Order tabs appear in the bar.
const _TAB_ORDER: Array[StringName] = [
	_TAB_OVERVIEW, _TAB_COMBAT, _TAB_MAGIC, _TAB_DEFENSE, _TAB_POOLS, _TAB_MISC, _TAB_ALL,
]

@export var board: StatBoard:
	set(value):
		_disconnect_board()
		board = value
		_connect_board()
		_rebuild()

# stat id → list of row Controls (one per tab the stat appears in — typically
# 2 entries: the category tab + the "All" tab). Refresh walks both.
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
	for tab_id in _TAB_ORDER:
		var vb := VBoxContainer.new()
		vb.name = _TAB_TITLES.get(tab_id, String(tab_id))
		_tab_container.add_child(vb)
		per_tab[tab_id] = vb

	var defs := _collect_visible_defs()
	defs.sort_custom(func(a, b): return a.display_order < b.display_order)
	for def in defs:
		var cat: StringName = _CATEGORY.get(def.id, _TAB_MISC)
		_add_row_to_tab(def, per_tab[cat])
		_add_row_to_tab(def, per_tab[_TAB_ALL])
		_refresh(def.id)

	# Hide tabs with no rows — empty tabs are clutter.
	for tab_id in _TAB_ORDER:
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
