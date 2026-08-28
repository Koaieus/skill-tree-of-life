@tool
extends ProgressBar

## Node combat health bar — shows the SkillNode's per-node HP pool (max vs
## current) via [method SkillNode.node_board]. Wires in _ready; visibility is
## automatic: hidden when unallocated or at full HP, fades in on hover or damage.
##
## [b]Query + subscription while shown (#660).[/b] The live subscriptions — the
## pool's `current_changed`/`value_changed` and the owner's
## [signal Entity.node_health_cap_changed] — are scoped into a [SubBag] that is
## bound only while the bar is actually on screen and released the moment it
## fades out. The bar is on screen iff the node is damaged or hovered, so the
## entity-level cap signal carries O(visible) listeners rather than O(owned):
## a level's undamaged, unhovered nodes hold no subscription at all and do no
## per-node work when their owner's CON moves.
##
## What stays always-on is deliberately only the free, node-LOCAL triggers that
## decide whether to sprout: `owner_changed`, hover, and
## [signal SkillNode.damaged]. Those cost one listener on the node's own signals
## and never fan out from the entity — re-adding a per-node subscription to the
## entity board as a convenience is precisely what #660 deleted.
##
## The no-pop guarantee is [method SubBag.now]: the sprout connects and paints in
## one step, snapping `value`/`max_value` to the pool's live state *while alpha
## is still 0*, before the fade-in starts. So a bar that spent the last minute
## unsubscribed and stale can never render that stale fill — its first visible
## frame is already reconciled. Releasing is symmetric and invisible: `clear()`
## touches no drawing state, and the fade-out and value tweens already in flight
## are animations, not subscriptions, so they run to completion unaffected.
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
## The owner whose entity-level [signal Entity.node_health_cap_changed] this bar
## subscribes to *while shown* (#660). The node pool's own `value_changed` no
## longer fires when the OWNER's `node_health` baseline moves — the cap is
## derived on read — so a visible bar hears it once, from the entity, and an
## invisible one does not hear it at all.
var _cap_source: Entity = null
## The show-scoped subscriptions. Everything in here is connected by
## [method _bind_live] and dropped by [method _release]; nothing outside those
## two methods connects to the pool or the entity.
var _subs := SubBag.new()
## Whether [member _subs] currently holds the live bindings. Guards the
## re-entrancy [method SubBag.now] introduces — its synchronous first call lands
## in [method _on_current_changed], which re-enters [method _update_visibility].
var _bound: bool = false


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
	# The sprout trigger, and the reason an undamaged node needs no pool
	# subscription: node-LOCAL, one listener, no entity fan-out.
	_skill_node.damaged.connect(_on_node_hp_event)
	_skill_node.healed.connect(_on_node_hp_event)

	# Deferred so SkillNode._ready() (parent) runs first — it creates the
	# node_board and refills combat health during _refresh_hp_binding.
	_on_owner_changed.call_deferred()


## Re-target at whichever `node_health` pool and owner this node now has. The
## live bindings are released first: they point at the *previous* pool/entity,
## and [method _update_visibility] re-sprouts against the new pair if the bar is
## still meant to be on screen.
func _on_owner_changed() -> void:
	if _skill_node == null:
		return
	_release()
	var allocated := _skill_node.is_allocated()
	_pool = _skill_node.node_board.get_stat(&"node_health") as PoolStat \
			if allocated and _skill_node.node_board != null else null
	_cap_source = _skill_node.owned_by if allocated else null
	_update_visibility()


# ── Show-scoped bindings ────────────────────────────────────────────────────

## Connect the live sources and paint once, atomically ([method SubBag.now] —
## a read-then-subscribe done as two steps leaves a gap in which the pool can
## move, and the bar would fade in showing the value from before it).
##
## `current_changed` carries the fill; `value_changed` carries a NODE-LOCAL cap
## move; [signal Entity.node_health_cap_changed] carries an owner-baseline cap
## move. The last one is why this bag exists.
func _bind_live() -> void:
	if _bound or _pool == null:
		return
	_bound = true
	_subs.on(_pool.current_changed, _on_current_changed)
	if _cap_source != null:
		_subs.on(_cap_source.node_health_cap_changed, _on_max_changed)
	# Last, and via `now()`: every connect above is already in place, so its
	# zero-arg synchronous call is a first paint with no gap in front of it.
	_subs.now(_pool.value_changed, _on_max_changed)


## Drop every show-scoped subscription. Idempotent, and safe against a freed
## pool or entity ([SubBag] delegates that tolerance to [BindScope]).
func _release() -> void:
	if not _bound:
		return
	_bound = false
	_subs.clear()


# ── Pool signal handlers ────────────────────────────────────────────────────

## The node's combat HP moved. Damage snaps down fast, healing eases back up —
## the tween is pure animation over a value the model has already committed to,
## and gates nothing.
##
## The emitted value is ignored in favour of a fresh read: [method SubBag.now]
## invokes this with no arguments at all, and the pool is the authority either
## way (see the [SubBag] class doc).
func _on_current_changed(_new_current: Variant = null) -> void:
	if _pool == null:
		return
	var hp := float(_pool.current)
	if is_zero_approx(modulate.a) and is_zero_approx(_fade_target):
		# First paint of a sprout: the bar is invisible, so snap rather than
		# tween. Tweening from a stale fill IS the visible pop.
		_kill_value_tween()
		value = hp
	elif hp < value:
		_tween_value(hp, _DMG_DURATION, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	else:
		_tween_value(hp, _HEAL_DURATION, Tween.EASE_IN_OUT, Tween.TRANS_CUBIC)
	_update_visibility()


## The cap moved — from a node-local modifier (the pool's own `value_changed`)
## or from the owner's baseline ([signal Entity.node_health_cap_changed]).
##
## Re-reads `current` as well, and must: this pool stores DAMAGE TAKEN
## ([method PoolStat.stores_missing]), so a cap move IS a current move, and no
## `current_changed` accompanies it.
func _on_max_changed() -> void:
	if _pool == null:
		return
	max_value = _pool.value
	_on_current_changed()


# ── Hover ───────────────────────────────────────────────────────────────────

func _on_hovered() -> void:
	_hovered = true
	_update_visibility()


func _on_unhovered() -> void:
	_hovered = false
	_update_visibility()


## Node-local damage/heal announcement. While the bar is released this is the
## only thing that can wake it; while it is bound it is redundant with
## `current_changed` and costs one no-op visibility pass.
func _on_node_hp_event(_amount: float = 0.0, _source: Variant = null) -> void:
	_update_visibility()


# ── Visibility ──────────────────────────────────────────────────────────────

## The single gate: it decides whether the bar is on screen AND whether it holds
## live subscriptions, so the two can never disagree.
##
## `hp < max` counts as damaged: a depleted node must read as an empty bar, not
## as no bar at all. Only a node at full HP hides itself — and a hidden bar is
## an unsubscribed one.
func _update_visibility() -> void:
	if _pool == null:
		_release()
		return _fade_to(0.0)
	var hp := float(_pool.current)
	var shown: bool = _hovered or hp < _pool.value
	if shown:
		# Before the fade: `_bind_live`'s first paint must land while alpha is
		# still 0 for the snap-not-tween branch above to fire.
		_bind_live()
		_fade_to(1.0)
	else:
		_fade_to(0.0)
		_release()


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

func _kill_value_tween() -> void:
	if _value_tween:
		_value_tween.kill()
		_value_tween = null


func _tween_value(target: float, duration: float,
		_ease: Tween.EaseType, trans: Tween.TransitionType) -> void:
	_kill_value_tween()
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
