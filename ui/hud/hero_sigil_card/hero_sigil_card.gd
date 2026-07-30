@tool
class_name HeroSigilCard
extends MarginContainer

## Left column, top card (#108): class emblem (spinning ring + glyph), level
## badge, entity name + class subtitle, Health/Mana/XP as [PoolGauge]s with
## dimmed "+N/t" regen captions. Also the floater-anchor origin for
## entity/core stat-change toasts (closes #91) — see [member float_anchor]
## and [method GameRoot]'s wiring of [FloaterDirector.player_anchor].
##
## Root is a 0-margin MarginContainer (not a plain Control) so its reported
## minimum size aggregates its children's — a plain Control reports (0,0)
## regardless of content, which collapsed this card to zero height inside
## HudRoot's LeftColumnSlot VBoxContainer. See combat_readout_card.gd for
## the same pattern/writeup (shared bug across all HUD cards).

@onready var _panel: GlassPanel = %GlassPanel
@onready var _emblem_ring: Control = %EmblemRing
@onready var _emblem_glyph: Label = %EmblemGlyph
@onready var _sigil_glyph: SigilGlyph = %SigilGlyph
@onready var _level_badge: Label = %LevelBadge
@onready var _name_label: Label = %NameLabel
@onready var _class_label: Label = %ClassLabel
@onready var _health_gauge: PoolGauge = %HealthGauge
@onready var _health_caption: Label = %HealthCaption
@onready var _mana_gauge: PoolGauge = %ManaGauge
@onready var _mana_caption: Label = %ManaCaption
@onready var _xp_gauge: PoolGauge = %XPGauge
@onready var _xp_caption: Label = %XPCaption

## World/UI-space anchor floaters rise from (stat gains, wounds, level-ups).
## A plain [Node2D] child works as a [FloaterRequest.target] unmodified —
## CanvasItem global transforms compose across the Control/Node2D boundary,
## so this resolves to screen pixels exactly like the Control it sits in.
@onready var float_anchor: Node2D = %FloatAnchor

## Radians/sec the emblem ring spins. Time-uniform driven (not gated to
## runtime-only) so it animates in the editor too, per the @tool contract.
@export_range(0.0, 2.0, 0.01) var emblem_spin_speed: float = 0.35

var _entity: Entity


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _emblem_ring != null:
		_emblem_ring.rotation += delta * emblem_spin_speed


func bind(entity: Entity) -> void:
	if _entity != null:
		_disconnect_entity()
	_entity = entity
	if _entity == null:
		return

	_name_label.text = _entity.display_name
	_class_label.text = _entity.core_class.display_name if _entity.core_class != null else "Allround"
	var sigil: Sigil = _entity.core_class.sigil if _entity.core_class != null else null
	_sigil_glyph.sigil = sigil
	_sigil_glyph.visible = sigil != null
	_emblem_glyph.visible = sigil == null  # fallback glyph for classes with no sigil authored
	_level_badge.text = str(_entity.level)
	_entity.leveled_up.connect(_on_leveled_up)

	var board := _entity.stat_board
	if board == null:
		return
	# `core_healing` is health's per-turn companion (D-25) — same "incoming next
	# turn" band mana and XP already render, which is exactly why D-25 chose an
	# integer heal over a sub-1 sliver: zero new UI.
	_bind_pool(_health_gauge, _health_caption, board.health, board.core_healing)
	_bind_pool(_mana_gauge, _mana_caption, board.mana, board.mana_per_turn)
	# XP gets its own binding so a level-up plays a fill→wrap→fill animation
	# instead of the raw pool edits collapsing into a downward jump (#154).
	_bind_xp(board.xp, board.xp_per_turn)


func _disconnect_entity() -> void:
	if _entity.leveled_up.is_connected(_on_leveled_up):
		_entity.leveled_up.disconnect(_on_leveled_up)


func _on_leveled_up(new_level: int) -> void:
	_level_badge.text = str(new_level)


# ── XP gauge (#154): level-up-aware binding ──────────────────────────────────

var _xp_pool: PoolStat
var _xp_per_turn: ScalarStat
## The gauge's last settled state — the "before" of a level-up, since the pool
## already holds the "after" by the time the level-up is observable.
var _xp_shown_current: float = 0.0
var _xp_shown_max: float = 0.0
var _xp_apply_queued: bool = false
var _xp_leveled: bool = false


func _bind_xp(pool: PoolStat, per_turn: ScalarStat) -> void:
	if _xp_gauge == null or pool == null:
		return
	_xp_pool = pool
	_xp_per_turn = per_turn
	_xp_shown_current = float(pool.current)
	_xp_shown_max = float(pool.value)
	_xp_gauge.min_value = 0.0
	_xp_gauge.max_value = _xp_shown_max
	_xp_gauge.current = _xp_shown_current
	_xp_gauge.preview_gain = float(per_turn.value) if per_turn != null else 0.0
	pool.current_changed.connect(func(_v): _on_xp_changed())
	pool.value_changed.connect(_on_xp_changed)
	# `replenished` fires once per level-up (pool crossed its cap), after the
	# synchronous grow+reset — a reliable flag for the coalesced apply below.
	pool.replenished.connect(func(): _xp_leveled = true)
	if per_turn != null:
		per_turn.value_changed.connect(func(): _xp_gauge.preview_gain = float(per_turn.value))
		per_turn.value_changed.connect(_refresh_xp_caption)
	_refresh_xp_caption()


func _on_xp_changed() -> void:
	_refresh_xp_caption()
	# Coalesce the level-up's fill→grow→reset burst (three synchronous edits) into
	# one deferred apply, so we compare the settled "before" to the final "after".
	if _xp_apply_queued:
		return
	_xp_apply_queued = true
	_apply_xp.call_deferred()


func _apply_xp() -> void:
	_xp_apply_queued = false
	if _xp_pool == null or _xp_gauge == null:
		return
	var new_current := float(_xp_pool.current)
	var new_max := float(_xp_pool.value)
	if _xp_leveled:
		_xp_leveled = false
		_xp_gauge.play_level_up(_xp_shown_current, _xp_shown_max, new_current, new_max)
	else:
		_xp_gauge.max_value = new_max
		_xp_gauge.current = new_current
	_xp_shown_current = new_current
	_xp_shown_max = new_max


func _refresh_xp_caption() -> void:
	if _xp_caption == null or _xp_pool == null:
		return
	if _xp_per_turn != null and float(_xp_per_turn.value) > 0.0:
		_xp_caption.text = "%d/%d (+%d/t)" % [int(_xp_pool.current), int(_xp_pool.value), int(_xp_per_turn.value)]
	else:
		_xp_caption.text = "%d/%d" % [int(_xp_pool.current), int(_xp_pool.value)]


func _bind_pool(gauge: PoolGauge, caption: Label, pool: PoolStat, per_turn: ScalarStat) -> void:
	if gauge == null or pool == null:
		return
	gauge.min_value = 0.0
	gauge.max_value = float(pool.value)
	gauge.current = float(pool.current)
	gauge.preview_gain = float(per_turn.value) if per_turn != null else 0.0
	pool.current_changed.connect(func(v): gauge.current = float(v))
	pool.value_changed.connect(func(): gauge.max_value = float(pool.value))
	if per_turn != null:
		per_turn.value_changed.connect(func(): gauge.preview_gain = float(per_turn.value))
	if caption != null:
		var refresh_caption := func():
			if per_turn != null and float(per_turn.value) > 0.0:
				caption.text = "%d/%d (+%d/t)" % [int(pool.current), int(pool.value), int(per_turn.value)]
			else:
				caption.text = "%d/%d" % [int(pool.current), int(pool.value)]
		pool.current_changed.connect(refresh_caption.unbind(1))
		pool.value_changed.connect(refresh_caption)
		if per_turn != null:
			per_turn.value_changed.connect(refresh_caption)
		refresh_caption.call()
