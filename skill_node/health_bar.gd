extends ProgressBar

## Visibility: hidden at full HP (or when unowned); fades in when damaged or hovered.
## Value: tweens smoothly on damage (fast snap down) and heal (slower fill).
## Wires itself to its owner SkillNode in _ready — no external injection needed.

const _FADE_IN_DURATION  := 0.12
const _FADE_OUT_DURATION := 0.45

const _DMG_DURATION  := 0.18
const _HEAL_DURATION := 0.45

const _COLOR_FULL := Color(0.18, 0.79, 0.17, 1.0)
const _COLOR_MID  := Color(1.0, 0.65, 0.0,  1.0)
const _COLOR_LOW  := Color(1.0, 0.22, 0.22, 1.0)

var _fill_style: StyleBoxFlat = null
var _skill_node: SkillNode = null
var _hovered: bool = false
var _fade_tween: Tween = null
var _value_tween: Tween = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	var existing := get_theme_stylebox("fill")
	_fill_style = existing.duplicate() if existing is StyleBoxFlat else StyleBoxFlat.new()
	add_theme_stylebox_override("fill", _fill_style)

	_skill_node = owner as SkillNode
	if _skill_node == null:
		return

	_skill_node.damaged.connect(_on_damaged)
	_skill_node.healed.connect(_on_healed)
	_skill_node.owner_changed.connect(_sync, CONNECT_DEFERRED)
	_skill_node.mouse_entered.connect(_on_hovered)
	_skill_node.mouse_exited.connect(_on_unhovered)

	# Deferred so SkillNode._ready() (parent) has a chance to run first —
	# it calls _refresh_hp_binding() which sets current_hp to max. Without
	# this, _sync() sees current_hp=0 + owned_by!=null → false "damaged" state.
	call_deferred(&"_sync")


# ── HP signal handlers ────────────────────────────────────────────────────────

func _on_damaged(_amount: float, _source: Variant) -> void:
	max_value = _skill_node.get_max_hp()
	_tween_value(_skill_node.current_hp, _DMG_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	_update_visibility()


func _on_healed(_amount: float, _source: Variant) -> void:
	max_value = _skill_node.get_max_hp()
	_tween_value(_skill_node.current_hp, _HEAL_DURATION, Tween.EASE_IN_OUT, Tween.TRANS_CUBIC)
	_update_visibility()


# ── Hover handlers ────────────────────────────────────────────────────────────

func _on_hovered() -> void:
	_hovered = true
	_update_visibility()


func _on_unhovered() -> void:
	_hovered = false
	_update_visibility()


# ── Sync (owner change / init) ────────────────────────────────────────────────

func _sync() -> void:
	if _skill_node == null:
		return
	max_value = _skill_node.get_max_hp()
	value = _skill_node.current_hp
	_update_visibility()


# ── Visibility ────────────────────────────────────────────────────────────────

func _update_visibility() -> void:
	var damaged := _skill_node != null \
			and _skill_node.owned_by != null \
			and _skill_node.current_hp > 0.0 \
			and _skill_node.current_hp < _skill_node.get_max_hp()
	_fade_to(1.0 if (_hovered or damaged) else 0.0)


func _fade_to(target_alpha: float) -> void:
	if is_equal_approx(modulate.a, target_alpha):
		return
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	var dur := _FADE_IN_DURATION if target_alpha > 0.0 else _FADE_OUT_DURATION
	_fade_tween.tween_property(self, "modulate:a", target_alpha, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# ── Value tween ───────────────────────────────────────────────────────────────

func _tween_value(target: float, duration: float,
		ease: Tween.EaseType, trans: Tween.TransitionType) -> void:
	if _value_tween:
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, duration) \
			.set_ease(ease).set_trans(trans)


# ── Color by ratio (called automatically via value_changed signal) ────────────

func _on_value_changed(new_value: float) -> void:
	if _fill_style == null:
		return
	var ratio := new_value / max_value if max_value > 0.0 else 0.0
	if ratio <= 0.25:
		_fill_style.bg_color = _COLOR_LOW
	elif ratio <= 0.65:
		_fill_style.bg_color = _COLOR_MID
	else:
		_fill_style.bg_color = _COLOR_FULL
