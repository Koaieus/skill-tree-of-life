@tool
class_name CoreHealthBar
extends ProgressBar

## Entity core health bar — shows the owning entity's [member PoolStat.current]
## vs its max. Wired externally by [method SkillNode._refresh_core_health_bar];
## the bar manages its own signal bindings and fade animation via [method bind_health].

const _FADE_IN_DURATION  := 0.12
const _FADE_OUT_DURATION := 0.45

const _DMG_DURATION  := 0.18
const _HEAL_DURATION := 0.45

const _COLOR_FULL := Color(1.0,  0.82, 0.1,  1.0)
const _COLOR_MID  := Color(0.9,  0.40, 0.05, 1.0)
const _COLOR_LOW  := Color(0.85, 0.10, 0.10, 1.0)

var _fill_style: StyleBoxFlat = null
var _pool: PoolStat = null
## The entity this pool belongs to. Only tracked here for `view_health_changed`
## — the drawn `value` is driven exclusively by that signal, not by the pool's
## own `current_changed`; see #491. Null is a valid bind (no entity, no drawn
## lag — the bar just follows the pool directly).
var _entity: Entity = null
var _fade_tween: Tween = null
var _value_tween: Tween = null
## Committed fade target — see the same field in health_bar.gd (#147). Guards
## against early-returning while a fade tween is still driving alpha the other way.
var _fade_target: float = 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var existing := get_theme_stylebox("fill")
	_fill_style = existing.duplicate() if existing is StyleBoxFlat else StyleBoxFlat.new()
	add_theme_stylebox_override("fill", _fill_style)


## Bind to an entity's health [PoolStat] (pass [code]null[/code] to detach).
## [param entity] is the view-state anchor (#491) — its [signal
## Entity.view_health_changed] drives the drawn `value`, never the pool's own
## `current_changed`, so the bar lags the pool by however long
## [PresentationPlayer] takes to reveal a chip/overflow source. Fades in on
## bind, fades out on detach.
func bind_health(pool: PoolStat, entity: Entity = null) -> void:
	if _pool == pool and _entity == entity:
		return
	if _pool != null:
		if _pool.value_changed.is_connected(_on_max_changed):
			_pool.value_changed.disconnect(_on_max_changed)
	if _entity != null and _entity.view_health_changed.is_connected(_on_view_health_changed):
		_entity.view_health_changed.disconnect(_on_view_health_changed)
	_pool = pool
	_entity = entity
	if _pool != null:
		_pool.value_changed.connect(_on_max_changed)
		if _entity != null:
			_entity.view_health_changed.connect(_on_view_health_changed)
		_sync()
		_fade_to(1.0)
	else:
		_fade_to(0.0)


# ── Pool signal handlers ──────────────────────────────────────────────────────

## The entity's DRAWN health changed (#491) — [PresentationPlayer] is the
## single writer, so this fires on the exact cadence a chip/overflow source
## should visibly land (a staggered cascade steps this once per layer, same
## rhythm as the node paint ripple).
func _on_view_health_changed(shown_value: float) -> void:
	var going_down := shown_value < value
	if going_down:
		_tween_value(shown_value, _DMG_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	else:
		_tween_value(shown_value, _HEAL_DURATION, Tween.EASE_IN_OUT, Tween.TRANS_CUBIC)


func _on_max_changed() -> void:
	if _pool != null:
		max_value = _pool.value


func _sync() -> void:
	if _pool == null:
		return
	max_value = _pool.value
	value = _entity.shown_health if _entity != null else float(_pool.current)


# ── Fade ──────────────────────────────────────────────────────────────────────

func _fade_to(target_alpha: float) -> void:
	if is_equal_approx(_fade_target, target_alpha):
		return
	_fade_target = target_alpha
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	var dur := _FADE_IN_DURATION if target_alpha > 0.0 else _FADE_OUT_DURATION
	_fade_tween.tween_property(self, "modulate:a", target_alpha, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# ── Value tween ───────────────────────────────────────────────────────────────

func _tween_value(target: float, duration: float,
		ease_type: Tween.EaseType, trans: Tween.TransitionType) -> void:
	if _value_tween:
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, duration) \
			.set_ease(ease_type).set_trans(trans)


# ── Color by ratio (connected via value_changed in scene) ────────────────────

func _on_value_changed(new_value: float) -> void:
	if _fill_style == null:
		return
	var fill_ratio := new_value / max_value if max_value > 0.0 else 0.0
	if fill_ratio <= 0.25:
		_fill_style.bg_color = _COLOR_LOW
	elif fill_ratio <= 0.65:
		_fill_style.bg_color = _COLOR_MID
	else:
		_fill_style.bg_color = _COLOR_FULL
