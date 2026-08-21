@tool
class_name XpTrack
extends MarginContainer

## Top-center XP strip (#320): level, the XP gauge itself, the "+N XP" chip, and
## the running count. Lifted wholesale out of [HeroSigilCard], where XP was one
## 110px gauge in a corner card stacked under health and mana — third billing for
## the currency the whole game is denominated in. Skill points buy nodes, nodes
## are the game, and levels mint skill points; the bar that tracks that belongs
## across the top of the screen, not in a vitals list.
##
## It sits ABOVE the [InitiativeBar] and is drawn after it, so the initiative
## panel's turn-start exit slides north *behind* this strip — and the per-turn XP
## grant lands on a track that is, at that exact moment, the only thing at the
## top of the screen.
##
## Root is a 0-margin MarginContainer (not a plain Control) so its reported
## minimum size aggregates its children's — see [HeroSigilCard] for the same
## pattern and the bug that motivated it.
##
## The model is instant and authoritative — one `xp.replenish()` applies every
## level it crosses before anything here runs. What lives below is purely a
## REPLAY: a [PoolLevelSequencer] records the cascade as an ordered queue of
## level segments, and the gauge plays them one at a time, each ending with a
## beat at the full bar that fires [signal level_reached].
##
## Playback is chained off [signal PoolGauge.fill_finished] rather than baked
## into one tween, which is what makes interruption free: XP landing mid-replay
## (passive per-turn income is the main source, and lands in the same turn as a
## kill reward) just APPENDS to the queue. No tween is ever killed, so there is
## no stale "shown" state to reconstruct — the "from" is always the gauge's live
## value and the final target is always re-read from the pool at drain time.

## A level crossing reached its beat on the XP bar (#317). Fires once per level,
## in ascending order, paced by the gauge — NOT by the model, which has already
## applied every level synchronously by the time the first bar fills. [HudRoot]
## hangs the LEVEL UP announcement off this, so banner and bar tell the same
## story at the same time.
signal level_reached(new_level: int)

## The level this strip is now DISPLAYING. Fires on every beat, and also on the
## settle-time re-sync — which is the difference that matters: a level granted
## outside the XP pool (a `+level` modifier is legal, see
## .claude/rules/stats-system.md) never crosses a cap, so it produces no beat.
## Anything mirroring the readout ([HeroSigilCard]'s badge) must ride this, not
## [signal level_reached]; anything narrating the *event* (the LEVEL UP banner)
## must ride `level_reached`, or a silent re-sync would pop a spurious banner.
signal level_display_changed(level: int)

@onready var _gauge: PoolGauge = %XPGauge
@onready var _caption: Label = %XPCaption
@onready var _level_label: Label = %LevelLabel
@onready var _chip: XpDeltaChip = %XPDeltaChip

enum _Phase {
	IDLE,
	SEGMENT,  ## a level crossing is playing; must not be restarted
	SETTLE,   ## the final tween to the pool's live state; safe to restart
}

var _entity: Entity
var _pool: PoolStat
var _per_turn: ScalarStat
var _seq: PoolLevelSequencer
var _apply_queued: bool = false
var _phase: _Phase = _Phase.IDLE
## The level the strip is currently showing. Advanced by the gauge's beats, not
## by the model — `stat_board.level` is already final when the replay starts.
var _shown_level: int = 1

## What this strip connects to the CURRENT hero's XP pool, released as a unit
## by [method _unbind] (#459 hot-seat handover).
var _binds := BindScope.new()


func bind(entity: Entity) -> void:
	_unbind()
	_entity = entity
	if _entity == null:
		return
	_shown_level = _entity.level
	_refresh_level_label()
	var board := _entity.stat_board
	if board == null:
		return
	_bind_pool(board.xp, board.xp_per_turn)


func _bind_pool(pool: PoolStat, per_turn: ScalarStat) -> void:
	if _gauge == null or pool == null:
		return
	_pool = pool
	_per_turn = per_turn
	_seq = PoolLevelSequencer.new(float(pool.value))
	_phase = _Phase.IDLE
	_gauge.min_value = 0.0
	_gauge.max_value = float(pool.value)
	_gauge.current = float(pool.current)
	_gauge.preview_gain = float(per_turn.value) if per_turn != null else 0.0
	if not _gauge.fill_finished.is_connected(_on_fill_finished):
		_gauge.fill_finished.connect(_on_fill_finished)
		_gauge.level_segment_held.connect(_on_level_segment_held)
	_binds.link(pool.current_changed, _on_current_changed)
	_binds.link(pool.value_changed, _on_value_changed)
	_binds.link(pool.replenished_by, _on_gained)
	if per_turn != null:
		_binds.link(per_turn.value_changed, _on_per_turn_changed)
	_refresh_caption()


## Symmetric teardown for [method bind] — the pool is a per-entity resource, so
## leaving these connected would keep replaying a previous entity's XP into this
## strip (and the sequencer would still hold its segments).
func _unbind() -> void:
	_binds.release()
	_entity = null
	_pool = null
	_per_turn = null
	_seq = null
	_phase = _Phase.IDLE


func _on_per_turn_changed() -> void:
	_gauge.preview_gain = float(_per_turn.value)
	_refresh_caption()


func _on_gained(amount: float) -> void:
	if _chip != null:
		_chip.show_delta(amount)


func _on_current_changed(_v: Variant) -> void:
	_refresh_caption()
	_queue_apply()


## The recording edge. `value_changed` is the ONLY signal that observes a
## multi-level cascade in ascending order — `replenished` unwinds in reverse.
## See [PoolLevelSequencer].
func _on_value_changed() -> void:
	_refresh_caption()
	if _seq != null:
		_seq.observe(float(_pool.current), float(_pool.value))
	_queue_apply()


## Coalesce a level-up's burst of synchronous edits into one end-of-frame kick,
## so playback starts from a settled pool rather than mid-cascade.
func _queue_apply() -> void:
	if _apply_queued:
		return
	_apply_queued = true
	_apply.call_deferred()


func _apply() -> void:
	_apply_queued = false
	if _pool == null or _gauge == null:
		return
	# Mid-SEGMENT the new segments simply wait their turn in the queue. Mid-
	# SETTLE they don't: that tween is already aimed at the target read when it
	# started, so without this kick a passive per-turn tick landing inside it
	# would never be shown. Restarting a settle is safe (no discrete beats);
	# restarting a segment would drop a level's beat, hence the distinction.
	if _phase == _Phase.IDLE or _phase == _Phase.SETTLE:
		_play_next()


func _play_next() -> void:
	var segment := _seq.pop() if _seq != null else null
	if segment != null:
		_phase = _Phase.SEGMENT
		_gauge.play_level_segment(segment.fill_to, segment.new_max)
		return
	_phase = _Phase.SETTLE
	_gauge.animate_to(float(_pool.current), float(_pool.value))


func _on_fill_finished() -> void:
	if _phase == _Phase.SETTLE:
		_phase = _Phase.IDLE
		# The readout is derived from beats we witnessed; re-sync so a level
		# granted outside the XP pool (or before this strip bound) can't leave it
		# permanently behind. Deliberately does NOT emit `level_reached` — no cap
		# was crossed, so there is no moment to narrate, only a number to correct.
		if _entity != null and _shown_level != _entity.level:
			_shown_level = _entity.level
			_refresh_level_label()
		return
	if _phase == _Phase.SEGMENT:
		_play_next()


## The beat at the full bar: this is where a level "happens" for the player.
func _on_level_segment_held(_new_max: float) -> void:
	_shown_level += 1
	_refresh_level_label()
	level_reached.emit(_shown_level)


## The single funnel for "the level readout changed" — every writer of
## `_shown_level` goes through here, so no mirror of the readout can be missed.
func _refresh_level_label() -> void:
	if _level_label != null:
		_level_label.text = "LEVEL %d" % _shown_level
	level_display_changed.emit(_shown_level)


func _refresh_caption() -> void:
	if _caption == null or _pool == null:
		return
	if _per_turn != null and float(_per_turn.value) > 0.0:
		_caption.text = "%d / %d  (+%d/t)" % [int(_pool.current), int(_pool.value), int(_per_turn.value)]
	else:
		_caption.text = "%d / %d" % [int(_pool.current), int(_pool.value)]
