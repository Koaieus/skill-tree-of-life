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
var _fade_tween: Tween = null
var _value_tween: Tween = null
## Committed fade target — see the same field in health_bar.gd (#147). Guards
## against early-returning while a fade tween is still driving alpha the other way.
var _fade_target: float = 0.0
## Bind-scoped pool subscriptions. This bar is one-per-ENTITY, not one-per-node,
## so it is not part of #660's fan-out problem — it uses [SubBag] for the other
## half of the contract: `now()` fuses the connect and the first paint, so a
## rebind can never fade in showing the previous owner's fill, and `clear()`
## replaces the hand-rolled `is_connected` guards this used to carry.
var _subs := SubBag.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var existing := get_theme_stylebox("fill")
	_fill_style = existing.duplicate() if existing is StyleBoxFlat else StyleBoxFlat.new()
	add_theme_stylebox_override("fill", _fill_style)


## Bind to an entity's health [PoolStat] (pass [code]null[/code] to detach).
## The bar draws that pool and nothing else (#504): both its max
## (`value_changed`) and its current (`current_changed`). Under design B a
## chip/overflow source mutates the pool at the landing's own `arrival_time`,
## so there is no view state to lag behind it. Fades in on bind, out on detach.
func bind_health(pool: PoolStat) -> void:
	if _pool == pool:
		return
	_subs.clear()
	_pool = pool
	if _pool == null:
		return _fade_to(0.0)
	_subs.on(_pool.current_changed, _on_current_changed)
	_subs.now(_pool.value_changed, _on_max_changed)
	_fade_to(1.0)


# ── Pool signal handlers ──────────────────────────────────────────────────────

## The entity's core health moved. A staggered cascade steps this once per
## landing, the same rhythm as the node paint.
func _on_current_changed(_new_current: Variant = null) -> void:
	if _pool == null:
		return
	var hp := float(_pool.current)
	if is_zero_approx(modulate.a) and is_zero_approx(_fade_target):
		# First paint of a (re)bind, while the bar is still invisible: snap.
		# Tweening from the previous owner's fill IS the visible pop.
		_kill_value_tween()
		value = hp
	elif hp < value:
		_tween_value(hp, _DMG_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	else:
		_tween_value(hp, _HEAL_DURATION, Tween.EASE_IN_OUT, Tween.TRANS_CUBIC)


## The cap moved, or a fresh bind is painting for the first time. Re-reads
## `current` too, so one call is a complete paint.
func _on_max_changed() -> void:
	if _pool == null:
		return
	max_value = _pool.value
	_on_current_changed()


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

func _kill_value_tween() -> void:
	if _value_tween:
		_value_tween.kill()
		_value_tween = null


func _tween_value(target: float, duration: float,
		ease_type: Tween.EaseType, trans: Tween.TransitionType) -> void:
	_kill_value_tween()
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
