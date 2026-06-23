class_name SegmentedPoolBar
extends HBoxContainer

## Renders a [PoolStat]'s max as N equal segments, each tinted per bucket.
## Two binding modes:
##   * [method bind_simple] — single-bucket pool (current vs. used). Used for
##     [code]deallocation_points[/code], [code]action_points[/code], etc.
##   * [method bind_skill_points] — four-bucket [SkillPointStat] (current,
##     used, wounded, staked), tooltips per bucket.
##
## A "pulse" modulate flash plays when the stat mutates so even subtle
## one-segment changes register peripherally. Segments are [ColorRect] children
## (one per unit) so per-segment tooltips work without custom mouse handling.

const SEGMENT_WIDTH: int = 16
const SEGMENT_HEIGHT: int = 22
const SEGMENT_GAP: int = 2
const PULSE_TIME: float = 0.22

# Tints — tuned for the dark UI panel background.
const _TINT_SPENDABLE := Color(1.0, 0.85, 0.30)        # gold ("blessed")
const _TINT_USED := Color(0.35, 0.40, 0.55)            # cool grey
const _TINT_WOUNDED := Color(0.85, 0.25, 0.25)         # red
const _TINT_STAKED := Color(0.65, 0.35, 0.85)          # purple
const _TINT_DEALLOC := Color(0.45, 0.85, 1.0)          # cyan

const _PULSE_FLASH := Color(1.0, 1.0, 1.0)
const _PULSE_HARM := Color(1.0, 0.5, 0.5)
const _PULSE_BLESS := Color(1.0, 1.0, 0.7)

enum _Mode { NONE, SIMPLE, SKILL_POINTS }
var _mode: _Mode = _Mode.NONE
var _pool: PoolStat = null
var _skill_points: SkillPointStat = null
var _simple_tint: Color = _TINT_DEALLOC
var _simple_label: String = ""

var _tween: Tween


func _ready() -> void:
	add_theme_constant_override(&"separation", SEGMENT_GAP)


## Single-bucket bind. `tint` colours the spendable run; the rest fall back
## to the standard "used" grey. `label` is folded into both tooltips.
func bind_simple(pool: PoolStat, tint: Color, label: String) -> void:
	_unbind()
	_pool = pool
	_simple_tint = tint
	_simple_label = label
	_mode = _Mode.SIMPLE
	if _pool != null:
		_pool.value_changed.connect(_refresh)
		_pool.current_changed.connect(_on_pool_current_changed)
	_refresh()


## Convenience wrapper for the deallocation-points styling.
func bind_deallocation(pool: PoolStat) -> void:
	bind_simple(pool, _TINT_DEALLOC, "Deallocation Points")


## Multi-bucket bind: current / used / wounded / staked, each tooltipped.
func bind_skill_points(sp: SkillPointStat) -> void:
	_unbind()
	_skill_points = sp
	_mode = _Mode.SKILL_POINTS
	if _skill_points != null:
		_skill_points.value_changed.connect(_refresh)
		_skill_points.current_changed.connect(_on_pool_current_changed)
		_skill_points.wounded_changed.connect(_refresh)
		_skill_points.staked_changed.connect(_refresh)
		_skill_points.wounds_applied.connect(_on_wounds_applied)
		_skill_points.stake_applied.connect(_on_stake_applied)
	_refresh()


func _unbind() -> void:
	if _pool != null:
		if _pool.value_changed.is_connected(_refresh):
			_pool.value_changed.disconnect(_refresh)
		if _pool.current_changed.is_connected(_on_pool_current_changed):
			_pool.current_changed.disconnect(_on_pool_current_changed)
	if _skill_points != null:
		var sp := _skill_points
		if sp.value_changed.is_connected(_refresh):
			sp.value_changed.disconnect(_refresh)
		if sp.current_changed.is_connected(_on_pool_current_changed):
			sp.current_changed.disconnect(_on_pool_current_changed)
		if sp.wounded_changed.is_connected(_refresh):
			sp.wounded_changed.disconnect(_refresh)
		if sp.staked_changed.is_connected(_refresh):
			sp.staked_changed.disconnect(_refresh)
		if sp.wounds_applied.is_connected(_on_wounds_applied):
			sp.wounds_applied.disconnect(_on_wounds_applied)
		if sp.stake_applied.is_connected(_on_stake_applied):
			sp.stake_applied.disconnect(_on_stake_applied)
	_pool = null
	_skill_points = null
	_mode = _Mode.NONE


func _refresh() -> void:
	for child in get_children():
		child.queue_free()
	match _mode:
		_Mode.SIMPLE:
			_emit_simple_segments()
		_Mode.SKILL_POINTS:
			_emit_skill_point_segments()
		_:
			pass


func _emit_simple_segments() -> void:
	if _pool == null:
		return
	var current := roundi(_pool.current)
	var cap := int(_pool.value)
	var used: int = maxi(0, cap - current)
	_emit_run(current, _simple_tint,
			"%s: %d / %d" % [_simple_label, current, cap])
	_emit_run(used, _TINT_USED,
			"%s spent: %d" % [_simple_label, used])


func _emit_skill_point_segments() -> void:
	var sp := _skill_points
	if sp == null:
		return
	_emit_run(roundi(sp.current), _TINT_SPENDABLE,
			"Spendable SP: %d" % roundi(sp.current))
	_emit_run(sp.used, _TINT_USED,
			"Used SP: %d (locked into allocated nodes)" % sp.used)
	_emit_run(sp.wounded, _TINT_WOUNDED,
			"Wounded SP: %d (heals over time)" % sp.wounded)
	_emit_run(sp.staked, _TINT_STAKED,
			"Staked SP: %d (locked into per-node reservations)" % sp.staked)


func _emit_run(n: int, color: Color, tooltip: String) -> void:
	for i in maxi(0, n):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(SEGMENT_WIDTH, SEGMENT_HEIGHT)
		seg.color = color
		seg.tooltip_text = tooltip
		add_child(seg)


func _on_pool_current_changed(_v: Variant) -> void:
	_refresh()
	_pulse(_PULSE_FLASH)


func _on_wounds_applied(_amount: int) -> void:
	_pulse(_PULSE_HARM)


func _on_stake_applied(_amount: int) -> void:
	_pulse(_PULSE_BLESS)


## Modulate flash that fades back to white. Replaces any in-flight pulse so
## rapid changes don't queue up.
func _pulse(tint: Color) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	modulate = tint
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color.WHITE, PULSE_TIME) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
