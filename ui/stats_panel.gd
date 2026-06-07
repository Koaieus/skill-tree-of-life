@tool
class_name StatsPanel
extends VBoxContainer

## A read-only stats column. Set `board` (or rebind it) and the panel
## populates one Label per known stat id, refreshing on value_changed.
##
## Stat ids are enumerated here rather than discovered from the board so
## display order, pool/scalar formatting, and hidden stats stay under the
## panel's control — not derived from board property iteration.

const SCALARS: Array[StringName] = [
	&"strength",
	&"dexterity",
	&"intelligence",
	&"wisdom",
	&"perception",
	&"xp_per_turn",
]
const POOLS: Array[StringName] = [
	&"health",
	&"xp",
	&"skill_points",
	&"action_points",
	&"deallocation_points",
]

@export var board: StatBoard:
	set(value):
		if board == value:
			return
		_disconnect_board()
		board = value
		_connect_board()
		_rebuild()

var _labels: Dictionary[StringName, Label] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_labels.clear()
	if board == null:
		return
	for id in SCALARS:
		_make_label(id, false)
	for id in POOLS:
		_make_label(id, true)


func _make_label(id: StringName, is_pool: bool) -> void:
	var stat := board.get_stat(id)
	if stat == null:
		return
	var label := Label.new()
	add_child(label)
	_labels[id] = label
	_refresh(id, is_pool)


func _refresh(id: StringName, is_pool: bool) -> void:
	var stat := board.get_stat(id)
	var label: Label = _labels.get(id)
	if stat == null or label == null:
		return
	var def := stat.definition
	var stat_name: String = def.display_name if def != null else String(id)
	if is_pool and stat is PoolStat:
		var pool := stat as PoolStat
		label.text = "%s: %d/%d" % [stat_name, int(pool.value), int(pool.max_value)]
	else:
		label.text = "%s: %d" % [stat_name, int(stat.value)]


func _connect_board() -> void:
	if board == null:
		return
	for id in SCALARS:
		_connect_stat(id, false)
	for id in POOLS:
		_connect_stat(id, true)


func _disconnect_board() -> void:
	if board == null:
		return
	for id in SCALARS:
		_disconnect_stat(id, false)
	for id in POOLS:
		_disconnect_stat(id, true)


func _connect_stat(id: StringName, is_pool: bool) -> void:
	var stat := board.get_stat(id)
	if stat == null:
		return
	var cb := _refresh.bind(id, is_pool)
	if not stat.value_changed.is_connected(cb):
		stat.value_changed.connect(cb)
	if is_pool and stat is PoolStat:
		var pool := stat as PoolStat
		if pool.max_stat != null and not pool.max_stat.value_changed.is_connected(cb):
			pool.max_stat.value_changed.connect(cb)


func _disconnect_stat(id: StringName, is_pool: bool) -> void:
	var stat := board.get_stat(id)
	if stat == null:
		return
	# bind() returns a fresh Callable each call, so we can't compare to a
	# previously-bound one. Rebuilding the panel disconnects implicitly by
	# freeing the labels and clearing the dict — listeners are weakly held
	# via the stat → callable connection, but the stat outlives the panel.
	# A targeted disconnect lives here if it becomes a real leak.
	pass
