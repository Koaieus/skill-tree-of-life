@tool
extends PanelContainer

## Status effects LIVE panel: apply any `effects/status/*.tres` to one node and
## watch it land, tick and decay — the pinned fan (NodeStats / EffectReadout /
## Core), the pinned HP bar, a vision ring and a damage log.
##
## The world is a scene-authored bench (`status_bench.tscn` and its inherited
## setups in [member setups]) hosted in a SubViewport. Reset frees the bench
## and instantiates the current setup again; nothing is undone in place.
##
## Explicit-step only: ▶ Tick turn calls `TurnManager.end_turn()` once, which
## with the bench's lone (scoped) Bearer rolls straight into its next
## `start_turn` — real upkeep plus the `Events.turn_started` status tick. No
## `_process`, timer or await ever drives the clock.

const _STATUS_DIR := "res://effects/status/"
const _ROW_SCENE: PackedScene = preload("res://addons/status_sandbox/resistance_row.tscn")

## The setups, in the order of `%SetupOption`'s authored items.
@export var setups: Array[PackedScene] = []

## The live bench (`status_bench.gd`); replaced on every Reset.
var bench: Node2D = null

var _defs: Array[StatusDef] = []
var _setup_index := 0
var _resistance_rows: Array[Node] = []

@onready var _setup_option: OptionButton = %SetupOption
@onready var _reset_button: Button = %ResetBtn
@onready var _tick_button: Button = %TickBtn
@onready var _status_option: OptionButton = %StatusOption
@onready var _power_spin: SpinBox = %PowerSpin
@onready var _apply_button: Button = %ApplyBtn
@onready var _clear_button: Button = %ClearBtn
@onready var _cure_spin: SpinBox = %CureSpin
@onready var _cure_button: Button = %CureBtn
@onready var _ring_toggle: CheckButton = %RingToggle
@onready var _stat_label: Label = %StatLabel
@onready var _resistances: Container = %Resistances
@onready var _world: SubViewport = %World
@onready var _bench_host: Node2D = %BenchHost
@onready var _log: RichTextLabel = %Log


## The SandboxLiveTab loader hook. Self-contained — nothing to route in.
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	_populate_statuses()
	_build_resistance_rows()
	_setup_option.item_selected.connect(select_setup)
	_reset_button.pressed.connect(reset)
	_tick_button.pressed.connect(tick_turn)
	_apply_button.pressed.connect(_on_apply_pressed)
	_clear_button.pressed.connect(clear_statuses)
	_cure_button.pressed.connect(func() -> void: cure(_cure_spin.value))
	_ring_toggle.toggled.connect(_on_ring_toggled)
	_world.size_changed.connect(_layout_world)
	# Events is global across every tab's world: each handler filters to this
	# bench's node.
	Events.skill_node_damaged.connect(_on_node_damaged)
	Events.skill_node_healed.connect(_on_node_healed)
	Events.skill_node_depleted.connect(_on_node_depleted)
	select_setup(0)


func _exit_tree() -> void:
	if Events.skill_node_damaged.is_connected(_on_node_damaged):
		Events.skill_node_damaged.disconnect(_on_node_damaged)
	if Events.skill_node_healed.is_connected(_on_node_healed):
		Events.skill_node_healed.disconnect(_on_node_healed)
	if Events.skill_node_depleted.is_connected(_on_node_depleted):
		Events.skill_node_depleted.disconnect(_on_node_depleted)


# --- Beats (public so a test drives exactly what a click does) ----------------

func select_setup(index: int) -> void:
	_setup_index = clampi(index, 0, setups.size() - 1)
	_setup_option.select(_setup_index)
	reset()


## Free the current bench (synchronously: its node's poison must not hear the
## next bench's first turn) and arm a fresh instance of the selected setup.
func reset() -> void:
	if bench != null and is_instance_valid(bench):
		bench.disarm()
		bench.free()
	bench = null
	if setups.is_empty() or setups[_setup_index] == null:
		return
	bench = setups[_setup_index].instantiate()
	_bench_host.add_child(bench)
	bench.arm()
	for row in _resistance_rows:
		bench.set_resistance(row.stat_id, row.get_value())
	bench.set_ring_visible(_ring_toggle.button_pressed)
	var tm: TurnManager = bench.turn_manager
	tm.turn_started.connect(_on_turn_started)
	bench.node.statuses_changed.connect(_log_statuses.bind(false))
	bench.bearer.statuses_changed.connect(_log_statuses.bind(true))
	if bench.bearer.stat_board.health != null:
		bench.bearer.stat_board.health.current_changed.connect(_on_bearer_hp_changed)
	_log_line("[b]⟲ %s[/b]" % _setup_option.get_item_text(_setup_index))
	_on_turn_started(bench.bearer)
	_layout_world()


func apply_status(def: StatusDef, power: float) -> void:
	if bench == null or def == null:
		return
	var si: StatusInstance = bench.apply_status(def, power)
	if si == null:
		_log_line("node unallocated — ⟲ Reset re-arms it")
		return
	var host := "Bearer" if si.host_kind == StatusInstance.HostKind.ENTITY else "Node"
	_log_line("apply %s ×%.2f → landed %.2f on %s" % [def.id, power, si.power, host])
	_refresh_stats()


## One explicit step of the bench's own clock.
func tick_turn() -> void:
	if bench == null:
		return
	if bench.bearer.is_dead:
		_log_line("Bearer is dead — ⟲ Reset re-arms it")
		return
	var tm: TurnManager = bench.turn_manager
	if tm.current_entity == null:
		tm.start_turn(bench.bearer)
	else:
		tm.end_turn()
	_refresh_stats()


func clear_statuses() -> void:
	if bench != null:
		bench.clear_statuses()
		_refresh_stats()


func cure(amount: float) -> void:
	if bench != null:
		bench.cure(amount)
		_log_line("cure %.1f" % amount)
		_refresh_stats()


func set_resistance(stat_id: StringName, value: float) -> void:
	for row in _resistance_rows:
		if row.stat_id == stat_id:
			row.get_node(^"%Slider").set_value_no_signal(value)
			row.get_node(^"%Value").text = "%.2f" % value
	if bench != null:
		bench.set_resistance(stat_id, value)
		_refresh_stats()


func get_log_text() -> String:
	return _log.get_parsed_text()


# --- Composition ---------------------------------------------------------------

## Every StatusDef under [constant _STATUS_DIR], sorted by id.
func _populate_statuses() -> void:
	_defs.clear()
	for f in DirAccess.get_files_at(_STATUS_DIR):
		var path := _STATUS_DIR + f.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var def := load(path) as StatusDef
		if def != null:
			_defs.append(def)
	_defs.sort_custom(func(a: StatusDef, b: StatusDef) -> bool: return a.id < b.id)
	_status_option.clear()
	for def in _defs:
		_status_option.add_item(def.display_name if def.display_name != "" else String(def.id))


## One slider per distinct resistance stat the defs read.
func _build_resistance_rows() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for def in _defs:
		var id := def.resistance_stat_id
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		var row := _ROW_SCENE.instantiate()
		_resistances.add_child(row)
		row.setup(id)
		row.changed.connect(set_resistance)
		_resistance_rows.append(row)


func _layout_world() -> void:
	if bench != null:
		bench.position = Vector2(_world.size) * 0.5


# --- Log -----------------------------------------------------------------------

func _on_turn_started(entity: Entity) -> void:
	if bench == null or entity != bench.bearer:
		return
	_log_line("[color=gray]── turn %d ──[/color]" % entity.turns_taken)
	_refresh_stats()


func _on_node_damaged(node: SkillNode, amount: float, source: HitInstance) -> void:
	if bench != null and node == bench.node:
		_log_line("[color=salmon]Node took %.2f damage%s[/color]" % [amount, _source_label(source)])
		_refresh_stats()


func _on_node_healed(node: SkillNode, amount: float, source: HitInstance) -> void:
	if bench != null and node == bench.node:
		_log_line("[color=palegreen]Node healed %.2f%s[/color]" % [amount, _source_label(source)])
		_refresh_stats()


func _on_node_depleted(node: SkillNode, _source: HitInstance) -> void:
	if bench != null and node == bench.node:
		_log_line("[color=orangered]Node depleted[/color]")
		_refresh_stats()


func _on_bearer_hp_changed(current: Variant) -> void:
	_log_line("Bearer HP → %.2f" % float(current))
	_refresh_stats()


func _log_statuses(on_entity: bool) -> void:
	if bench == null:
		return
	var rows: Array[NodeStatus] = bench.bearer.get_statuses() if on_entity \
			else bench.node.get_combat().get_statuses()
	var parts: PackedStringArray = []
	for s in rows:
		parts.append("%s %.2f" % [s.def.id, s.power])
	_log_line("%s statuses: %s" % ["Bearer" if on_entity else "Node",
			", ".join(parts) if not parts.is_empty() else "none"])
	_refresh_stats()


func _source_label(source: HitInstance) -> String:
	if source is StatusInstance and (source as StatusInstance).def != null:
		return " (%s)" % (source as StatusInstance).def.id
	return ""


func _log_line(bbcode: String) -> void:
	_log.append_text(bbcode + "\n")


func _refresh_stats() -> void:
	if bench == null:
		_stat_label.text = "—"
		return
	var node: SkillNode = bench.node
	var hp: PoolStat = bench.bearer.stat_board.health
	_stat_label.text = "Node HP %.1f/%.1f   Bearer HP %.1f/%.1f   vision %.0f px" % [
		node.get_current_hp(), node.get_max_hp(),
		hp.current if hp != null else 0.0, float(hp.value) if hp != null else 0.0,
		bench.get_vision_radius(),
	]


func _on_apply_pressed() -> void:
	var i := _status_option.selected
	if i >= 0 and i < _defs.size():
		apply_status(_defs[i], _power_spin.value)


func _on_ring_toggled(on: bool) -> void:
	if bench != null:
		bench.set_ring_visible(on)
