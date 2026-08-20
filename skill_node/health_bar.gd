@tool
extends ProgressBar

## Node combat health bar — shows the SkillNode's per-node HP pool (max vs
## current) via [method SkillNode.node_board]. Wires in _ready; visibility is
## automatic: hidden when unallocated or at full HP, fades in on hover or damage.
##
## [b]@tool[/b] so the editor-hosted Spell Playground shows live HP. That means
## `_ready` runs while `skill_node.tscn` itself is open — every property it
## writes there is a serialization candidate, so `modulate` and `value` are
## baked in the scene to match what `_ready` sets (see the @tool scene-baking
## gotcha in `.claude/rules/godot-workflow.md`).

const _FADE_IN_DURATION  := 0.12
const _FADE_OUT_DURATION := 0.45

const _DMG_DURATION  := 0.18
const _HEAL_DURATION := 0.45

const _COLOR_FULL := Color(0.18, 0.79, 0.17, 1.0)
const _COLOR_MID  := Color(1.0, 0.65, 0.0,  1.0)
const _COLOR_LOW  := Color(1.0, 0.22, 0.22, 1.0)

var _fill_style: StyleBoxFlat = null
var _pool: PoolStat = null
var _skill_node: SkillNode = null
var _hovered: bool = false
var _fade_tween: Tween = null
var _value_tween: Tween = null
## The alpha the current fade is committed to. Tracked separately from the live
## `modulate.a` because a fade tween can be mid-flight — comparing against the
## momentary alpha would let `_fade_to` early-return while a tween still drives
## alpha toward the *opposite* target, leaving the bar stuck (#147).
var _fade_target: float = 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	var existing := get_theme_stylebox("fill")
	_fill_style = existing.duplicate() if existing is StyleBoxFlat else StyleBoxFlat.new()
	add_theme_stylebox_override("fill", _fill_style)

	_skill_node = owner as SkillNode
	if _skill_node == null:
		return

	_skill_node.owner_changed.connect(_on_owner_changed, CONNECT_DEFERRED)
	_skill_node.mouse_entered.connect(_on_hovered)
	_skill_node.mouse_exited.connect(_on_unhovered)

	# Deferred so SkillNode._ready() (parent) runs first — it creates the
	# node_board and syncs combat health during _refresh_hp_binding.
	_on_owner_changed.call_deferred()


## Rebind to whichever `node_health` pool this node's current owner brings.
## The pool is the ONLY thing this bar draws (#504) — see [method _bind_pool].
func _on_owner_changed() -> void:
	if _skill_node == null:
		return
	var hp: PoolStat = null
	if _skill_node.is_allocated() and _skill_node.node_board != null:
		hp = _skill_node.node_board.get_stat(&"node_health") as PoolStat
	_bind_pool(hp)


## #504: the bar binds to the real `node_health` pool and draws it — both its
## max (`value_changed`) and its current (`current_changed`). There is no view
## store to lag behind: [OutcomeApplier] lands each hit at its own
## `arrival_time`, so the pool itself already changes on the beat the player is
## watching (see [BeatClock]).
func _bind_pool(pool: PoolStat) -> void:
	if _pool == pool:
		return
	if _pool != null:
		if _pool.value_changed.is_connected(_on_max_changed):
			_pool.value_changed.disconnect(_on_max_changed)
		if _pool.current_changed.is_connected(_on_current_changed):
			_pool.current_changed.disconnect(_on_current_changed)
	_pool = pool
	if _pool != null:
		_pool.value_changed.connect(_on_max_changed)
		_pool.current_changed.connect(_on_current_changed)
		_sync()
	_update_visibility()


## The node's combat HP moved. Damage snaps down fast, healing eases back up —
## the tween is pure animation over a value the model has already committed to,
## and gates nothing.
func _on_current_changed(new_current: Variant) -> void:
	var hp := float(new_current)
	if hp < value:
		_tween_value(hp, _DMG_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	else:
		_tween_value(hp, _HEAL_DURATION, Tween.EASE_IN_OUT, Tween.TRANS_CUBIC)
	_update_visibility_for(hp)


func _on_max_changed() -> void:
	if _pool != null:
		max_value = _pool.value


func _sync() -> void:
	if _pool == null:
		return
	max_value = _pool.value
	value = float(_pool.current)


# ── Hover ───────────────────────────────────────────────────────────────────

func _on_hovered() -> void:
	_hovered = true
	_update_visibility()


func _on_unhovered() -> void:
	_hovered = false
	_update_visibility()


# ── Visibility ──────────────────────────────────────────────────────────────

func _update_visibility() -> void:
	if _pool == null:
		return _fade_to(0.0)
	_update_visibility_for(float(_pool.current))


## `hp < max` counts as damaged: a depleted node must read as an empty bar,
## not as no bar at all. Only a node at full HP hides itself.
func _update_visibility_for(hp: float) -> void:
	if _pool == null:
		return _fade_to(0.0)
	var damaged: bool = hp < _pool.value
	_fade_to(1.0 if (_hovered or damaged) else 0.0)


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


# ── Value tween ─────────────────────────────────────────────────────────────

func _tween_value(target: float, duration: float,
		_ease: Tween.EaseType, trans: Tween.TransitionType) -> void:
	if _value_tween:
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, duration) \
			.set_ease(_ease).set_trans(trans)


# ── Color by ratio (connected via value_changed signal in scene) ────────────

func _on_value_changed(new_value: float) -> void:
	if _fill_style == null:
		return
	var ratio_ := new_value / max_value if max_value > 0.0 else 0.0
	if ratio_ <= 0.25:
		_fill_style.bg_color = _COLOR_LOW
	elif ratio_ <= 0.65:
		_fill_style.bg_color = _COLOR_MID
	else:
		_fill_style.bg_color = _COLOR_FULL
