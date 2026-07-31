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
@onready var _xp_chip: XpDeltaChip = %XPDeltaChip

## A level crossing reached its beat on the XP bar (#317). Fires once per level,
## in ascending order, paced by the gauge — NOT by the model, which has already
## applied every level synchronously by the time the first bar fills. [HudRoot]
## hangs the LEVEL UP announcement off this so banner and bar tell the same
## story at the same time.
signal level_reached(new_level: int)

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
	_shown_level = _entity.level
	_level_badge.text = str(_shown_level)

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
	_unbind_xp()


# ── XP gauge (#154/#317): level-up-aware binding ─────────────────────────────
#
# The model is instant and authoritative — one `xp.replenish()` applies every
# level it crosses before anything here runs. What lives below is purely a
# REPLAY: a [PoolLevelSequencer] records the cascade as an ordered queue of
# level segments, and the gauge plays them one at a time, each ending with a
# beat at the full bar that bumps the badge and fires [signal level_reached].
#
# Playback is chained off [signal PoolGauge.fill_finished] rather than baked
# into one tween, which is what makes interruption free: XP landing mid-replay
# (passive per-turn income is the main source, and lands in the same turn as a
# kill reward) just APPENDS to the queue. No tween is ever killed, so there is
# no stale "shown" state to reconstruct — the "from" is always the gauge's live
# value and the final target is always re-read from the pool at drain time.

enum _Phase {
	IDLE,
	SEGMENT,  ## a level crossing is playing; must not be restarted
	SETTLE,   ## the final tween to the pool's live state; safe to restart
}

var _xp_pool: PoolStat
var _xp_per_turn: ScalarStat
var _xp_seq: PoolLevelSequencer
var _xp_apply_queued: bool = false
var _phase: _Phase = _Phase.IDLE
## The level the badge is currently showing. Advanced by the gauge's beats, not
## by the model — `stat_board.level` is already final when the replay starts.
var _shown_level: int = 1


func _bind_xp(pool: PoolStat, per_turn: ScalarStat) -> void:
	if _xp_gauge == null or pool == null:
		return
	_xp_pool = pool
	_xp_per_turn = per_turn
	_xp_seq = PoolLevelSequencer.new(float(pool.value))
	_phase = _Phase.IDLE
	_xp_gauge.min_value = 0.0
	_xp_gauge.max_value = float(pool.value)
	_xp_gauge.current = float(pool.current)
	_xp_gauge.preview_gain = float(per_turn.value) if per_turn != null else 0.0
	if not _xp_gauge.fill_finished.is_connected(_on_xp_fill_finished):
		_xp_gauge.fill_finished.connect(_on_xp_fill_finished)
		_xp_gauge.level_segment_held.connect(_on_xp_level_segment_held)
	pool.current_changed.connect(_on_xp_current_changed)
	pool.value_changed.connect(_on_xp_value_changed)
	pool.replenished_by.connect(_on_xp_gained)
	if per_turn != null:
		per_turn.value_changed.connect(_on_xp_per_turn_changed)
	_refresh_xp_caption()


## Symmetric teardown for [method bind] — the pool is a per-entity resource, so
## leaving these connected would keep replaying a previous entity's XP into this
## card (and the sequencer would still hold its segments).
func _unbind_xp() -> void:
	if _xp_pool != null:
		_xp_pool.current_changed.disconnect(_on_xp_current_changed)
		_xp_pool.value_changed.disconnect(_on_xp_value_changed)
		_xp_pool.replenished_by.disconnect(_on_xp_gained)
	if _xp_per_turn != null:
		_xp_per_turn.value_changed.disconnect(_on_xp_per_turn_changed)
	_xp_pool = null
	_xp_per_turn = null
	_xp_seq = null
	_phase = _Phase.IDLE


func _on_xp_per_turn_changed() -> void:
	_xp_gauge.preview_gain = float(_xp_per_turn.value)
	_refresh_xp_caption()


func _on_xp_gained(amount: float) -> void:
	if _xp_chip != null:
		_xp_chip.show_delta(amount)


func _on_xp_current_changed(_v: Variant) -> void:
	_refresh_xp_caption()
	_queue_apply()


## The recording edge. `value_changed` is the ONLY signal that observes a
## multi-level cascade in ascending order — `replenished` unwinds in reverse.
## See [PoolLevelSequencer].
func _on_xp_value_changed() -> void:
	_refresh_xp_caption()
	if _xp_seq != null:
		_xp_seq.observe(float(_xp_pool.current), float(_xp_pool.value))
	_queue_apply()


## Coalesce a level-up's burst of synchronous edits into one end-of-frame kick,
## so playback starts from a settled pool rather than mid-cascade.
func _queue_apply() -> void:
	if _xp_apply_queued:
		return
	_xp_apply_queued = true
	_apply_xp.call_deferred()


func _apply_xp() -> void:
	_xp_apply_queued = false
	if _xp_pool == null or _xp_gauge == null:
		return
	# Mid-SEGMENT the new segments simply wait their turn in the queue. Mid-
	# SETTLE they don't: that tween is already aimed at the target read when it
	# started, so without this kick a passive per-turn tick landing inside it
	# would never be shown. Restarting a settle is safe (no discrete beats);
	# restarting a segment would drop a level's beat, hence the distinction.
	if _phase == _Phase.IDLE or _phase == _Phase.SETTLE:
		_play_next()


func _play_next() -> void:
	var segment := _xp_seq.pop() if _xp_seq != null else null
	if segment != null:
		_phase = _Phase.SEGMENT
		_xp_gauge.play_level_segment(segment.fill_to, segment.new_max)
		return
	_phase = _Phase.SETTLE
	_xp_gauge.animate_to(float(_xp_pool.current), float(_xp_pool.value))


func _on_xp_fill_finished() -> void:
	if _phase == _Phase.SETTLE:
		_phase = _Phase.IDLE
		# The badge is derived from beats we witnessed; re-sync so a level
		# granted outside the XP pool (or before this card bound) can't leave
		# it permanently behind.
		if _entity != null and _shown_level != _entity.level:
			_shown_level = _entity.level
			_level_badge.text = str(_shown_level)
		return
	if _phase == _Phase.SEGMENT:
		_play_next()


## The beat at the full bar: this is where a level "happens" for the player.
func _on_xp_level_segment_held(_new_max: float) -> void:
	_shown_level += 1
	_level_badge.text = str(_shown_level)
	level_reached.emit(_shown_level)


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
	# Tweened, not hard-cut (#317) — and `animate_to` deliberately only tweens
	# *gains*, so a wound still snaps down and leaves its drain trail behind.
	var animate := func(): gauge.animate_to(float(pool.current), float(pool.value))
	pool.current_changed.connect(animate.unbind(1))
	pool.value_changed.connect(animate)
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
