@tool
class_name SkillNode
extends Area2D

const ZLayers = preload("res://ui/z_layers.gd")

signal radius_changed
signal owner_changed
signal left_clicked(skill_node: SkillNode)
signal right_clicked(skill_node: SkillNode)
## Emitted on every take_damage call (even at 0 effective). Local twin of
## [signal Events.skill_node_damaged]; subscribe locally for per-node reactions
## (hit-flash lives right here), globally on the bus for UI like floating numbers.
signal damaged(amount: float, source: Variant)
## Emitted on every heal_damage call (even at 0 effective). Local twin of
## [signal Events.skill_node_damaged]; subscribe locally for per-node reactions
## (heal-flash lives right here)
signal healed(amount: float, source: Variant)
## Emitted when a non-core node's [member current_hp] reaches 0. Local twin of
## [signal Events.skill_node_depleted]; BattleSystem listens on the bus for the
## cascade dealloc.
signal depleted

# `owned_by` is the single source of truth for allocation:
# null  → unallocated
# !null → allocated
@export var owned_by: Entity = null:
	set(value):
		if owned_by == value:
			return
		owned_by = value
		owner_changed.emit()

## The modifier offerings this node carries — pushed onto an allocating
## entity's stat board by AllocationSystem. Node-level data, no behaviour.
@export var modifiers: Array[StatModifier] = []

## Persistent base-type identity colour (e.g. procgen's NodeTypeDef colour).
## Drives the BaseCircle border; survives allocation. Defaults to dim grey so
## a hand-placed node in dev_sandbox.tscn looks the same as before any procgen
## stamping.
@export var base_type_color: Color = Color.DIM_GRAY:
	set(value):
		base_type_color = value
		if is_node_ready():
			_sync_visuals()

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()
		_sync_visuals()

## Radius of the inner fill disk — what reads as "ownership" when allocated,
## and what VFX sizes effects against. Authored per-node so future archetypes
## can run flush (inner_radius == radius) or extra-recessed; pushed down to
## BaseCircle in _sync_visuals so BaseCircle has no inset policy of its own.
@export var inner_radius: float = 24.0:
	set(value):
		if is_equal_approx(inner_radius, value):
			return
		inner_radius = value
		_sync_visuals()

@export var self_loops: Array[Edge] = []

@onready var visuals: Node2D = $Visuals
@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_marker: Node2D = $Visuals/CoreMarker
@onready var core_health_bar: CoreHealthBar = $Visuals/CoreHealthBar # TODO: pull through vision system
@onready var _base_circle: Node2D = $Visuals/BaseCircle
@onready var _addon_anchor: Node2D = $Visuals/AddonAnchor
@onready var _collision: CollisionShape2D = $CollisionShape2D

# Owner subscription tracking — re-bound whenever `owned_by` changes so the
# CoreMarker reflects the *current* owner's core_location, not a stale one.
var _bound_owner: Entity = null

## Sensed-but-not-visible flag, written by VisionSystem on every recompute.
## Drives the faint outline render on BaseCircle. Not a stat — purely a
## per-frame render hint, no signals, no persistence.
var sensed: bool = false:
	set(value):
		if sensed == value:
			return
		sensed = value
		_apply_sensed_state()

## Sparse [StatBoard] for per-node localized stats. All fields start null;
## a stat is only allocated when a node-local modifier targets it (via an
## addon) or when the node is allocated (combat health pool). See
## [method StatBoard._ensure_stat].
var node_board: StatBoard = null

## Per-node allocation cap. `alloc_cap_max` defaults to 1 (single allocation
## slot); raise by 1 per stake via the entity's `skill_points.stake(1)` action.
## `alloc_count` mirrors live allocation: 0 = unowned, 1 = baseline, 2+ = staked.
## Pure node-local — these are not Stats and must never be registered with
## an entity StatBoard. If you want to scale modifier contributions by the
## stake count, read it directly off the SkillNode.
var alloc_cap_max: int = 1
var alloc_count: int = 0

# Track the entity node_health stat so we can re-sync the node's combat health
# base_value when the entity baseline changes. Swap on owner_changed.
var _bound_entity_node_health: Stat = null

# Hit-flash bookkeeping. Killed and re-created on every hit so back-to-back
# damage doesn't visually merge into one stuck red.
var _hit_flash_tween: Tween

# Denial-feedback bookkeeping (#89). Killed + reset on every trigger so spamming
# the deallocate key doesn't stack shakes / leave a stuck offset or tint.
var _feedback_tweens: Array[Tween] = []

var self_loop_count: int:
	get(): return self_loops.size()

func _ready() -> void:
	_sync_collision()
	_sync_visuals()
	radius_changed.connect(_sync_visuals)
	owner_changed.connect(_sync_visuals)
	owner_changed.connect(_refresh_core_marker)
	owner_changed.connect(_refresh_hp_binding)
	owner_changed.connect(_refresh_alloc_count)
	damaged.connect(play_hit_flash.unbind(2))
	_addon_anchor.child_entered_tree.connect(_on_addon_added)
	_addon_anchor.child_exiting_tree.connect(_on_addon_removed)
	_refresh_core_marker()
	_refresh_hp_binding()


func _refresh_core_marker() -> void:
	if _bound_owner != owned_by:
		if _bound_owner != null and _bound_owner.core_location_changed.is_connected(_refresh_core_marker):
			_bound_owner.core_location_changed.disconnect(_refresh_core_marker)
		_bound_owner = owned_by
		if _bound_owner != null:
			_bound_owner.core_location_changed.connect(_refresh_core_marker)
	var is_core := owned_by != null and owned_by.core_location == self
	core_marker.visible = (not sensed) and is_core
	_refresh_core_health_bar(is_core)


func _refresh_core_health_bar(is_core: bool) -> void:
	var pool: PoolStat = null
	if is_core and owned_by != null and owned_by.stat_board != null:
		pool = owned_by.stat_board.health
	core_health_bar.bind_health(pool)
	core_health_bar.visible = (not sensed) and is_core


## Mirror the `sensed` flag onto the visual stack. Three things shift:
## the BaseCircle switches to its outline-only draw, the SkillNode is
## promoted above the fog overlay's z so the outline isn't dimmed into
## nothing, and owner/mechanic detail (core marker, addons) is hidden so
## a sensed-only viewer reads archetype only. The hide is a global
## placeholder — proper per-viewer info gating is the next layer up
## (see docs/domain/vision-system.md).
func _apply_sensed_state() -> void:
	if not is_node_ready():
		return
	if _base_circle != null:
		_base_circle.sensed = sensed
	z_as_relative = not sensed
	z_index = ZLayers.SENSED if sensed else ZLayers.GRAPH_DEFAULT
	var _is_core := owned_by != null and owned_by.core_location == self
	core_marker.visible = (not sensed) and _is_core
	core_health_bar.visible = (not sensed) and _is_core
	for a in get_addons():
		a.visible = not sensed


func _sync_collision() -> void:
	if _collision == null or _collision.shape == null:
		return
	(_collision.shape as CircleShape2D).radius = radius


func _sync_visuals() -> void:
	if not is_node_ready():
		return
	# Border = base-type identity (persistent). Fill = owner colour when
	# allocated, dim-grey idle otherwise. Two channels so allocation status
	# never wipes the type read.
	_base_circle._radius = radius
	_base_circle.inner_radius = inner_radius
	_base_circle.border_color = base_type_color
	_base_circle.fill_color = get_owner_color() if is_allocated() else Color.DIM_GRAY
	_base_circle.allocated = is_allocated()
	_base_circle.sensed = sensed
	_base_circle.queue_redraw()
	core_marker.configure(radius, get_owner_color())
	hover_ring.configure(radius)
	for a in get_addons():
		a.configure_visual(radius)


func is_allocated() -> bool:
	return owned_by != null


func is_core() -> bool:
	return owned_by != null and owned_by.core_location == self


func get_owner_color() -> Color:
	if owned_by:
		return owned_by.color
	return Color.WHITE


## World-space point on this node's perimeter facing [param world_target],
## plus optional [param extra_pad] outward. Use for projectile spawns,
## directional badges, or any anchor that should sit on the visible boundary.
func edge_point(world_target: Vector2, extra_pad: float = 0.0) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * (radius + extra_pad)


## Ring band convention (#67) — the single source of truth for how every
## decorative ring around a node expresses its span. A ring is a stroke of
## [param width] whose INNER edge sits [param inner_offset] outward from the
## node's canonical [member radius] (negative `inner_offset` insets the ring,
## so it lies inside the boundary). Returns the stroke CENTERLINE — the radius
## `draw_arc` / `draw_circle(..., filled=false, width)` actually want.
##   inner edge  = radius + inner_offset
##   outer edge  = radius + inner_offset + width
##   centerline  = radius + inner_offset + width / 2   ← returned
## `radius` itself is never redefined by this — it stays the collision /
## edge_point / blade-sim boundary; rings are purely relative to it. Filled
## discs (wash, inner disk) are NOT rings and don't use this. See
## `.claude/rules/skill-node-visuals.md` for the band table.
static func ring_centerline(node_radius: float, inner_offset: float, width: float) -> float:
	return node_radius + inner_offset + width / 2.0


## World-space pair `[start, end]` of a segment between [param a] and
## [param b], trimmed to each node's perimeter (plus [param pad] on each end).
## Returns an empty array when the nodes overlap so callers can early-out
## instead of drawing through each other. Static so it reads naturally at
## the call site: `SkillNode.segment_between(from, to)`.
static func segment_between(a: SkillNode, b: SkillNode, pad: float = 0.0) -> PackedVector2Array:
	if a == null or b == null:
		return PackedVector2Array()
	var pa := a.global_position
	var pb := b.global_position
	var delta := pb - pa
	var dist := delta.length()
	var trim_total: float = a.radius + b.radius + pad * 2.0
	if dist <= trim_total:
		return PackedVector2Array()
	var dir := delta / dist
	return PackedVector2Array([
		pa + dir * (a.radius + pad),
		pb - dir * (b.radius + pad),
	])


# ── Combat HP ──────────────────────────────────────────────────────────────

## Max combat HP for this node. Reads the node's [member node_board] combat
## health pool, which is seeded from the owning entity's [code]node_health[/code]
## baseline + any node-local modifiers. 0 if unallocated.
func get_max_hp() -> float:
	if node_board == null:
		return 0.0
	var hp := node_board.get_stat(&"node_health") as PoolStat
	if hp == null:
		return 0.0
	return hp.value


## Current combat HP for this node (ephemeral, from the pool's [member PoolStat.current]).
func get_current_hp() -> float:
	if node_board == null:
		return 0.0
	var hp := node_board.get_stat(&"node_health") as PoolStat
	if hp == null:
		return 0.0
	return hp.current


## Non-allocating passthrough read: returns the combined value of a stat
## visible to this node (entity board if owned, or StatRegistry default if
## orphaned). Does NOT create a stat on [member node_board] — use
## [method _ensure_local_stat] when you need a modifier target.
func get_local_value(stat_id: StringName) -> Variant:
	if owned_by != null and owned_by.stat_board != null:
		var es := owned_by.stat_board.get_stat(stat_id)
		if es != null:
			var ns: Stat = node_board.get_stat(stat_id) if node_board != null else null
			if ns == null:
				return es.get_value()
			var sources: Array[ModifierBins] = [es.bins, ns.bins]
			return ModifierBins.compute(es.base_value, sources)
	var ns: Stat = node_board.get_stat(stat_id) if node_board != null else null
	if ns != null:
		return ns.get_value()
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def != null:
		return def.default_value
	return 0.0


## Returns (creating if necessary) the [code]node_board[/code] stat for
## [param stat_id]. This IS the modifier target — callers that just need a
## value should use [method get_local_value] instead, which does not allocate.
##
## When [param stat_id] is "node_health", a PoolStat is created (using the
## [code]node_combat_health[/code] PoolStatDef for its settings) instead of
## a ScalarStat — the entity board already owns the ScalarStat baseline;
## the node board needs the combat pool (max + current).
func _ensure_local_stat(stat_id: StringName) -> Stat:
	_init_node_board()
	if stat_id == &"node_health":
		var existing := node_board.get_stat(stat_id)
		if existing != null:
			return existing
		var def: StatDef = StatRegistry.get_def(&"node_combat_health")
		if def != null:
			var hp := PoolStat.new()
			hp.definition = def
			hp.base_value = def.default_value
			node_board._extra_stats[stat_id] = hp
			return hp
	return node_board._ensure_stat(stat_id)


func get_addons() -> Array[SkillNodeAddon]:
	var out: Array[SkillNodeAddon] = []
	if _addon_anchor == null:
		return out
	for c in _addon_anchor.get_children():
		if c is SkillNodeAddon:
			out.append(c)
	return out


## Tooltip sections contributed by attached addons. Each entry is
## `{ "title": String, "modifiers": Array[StatModifier] }`; SkillNodeTooltip
## renders them below the node's own modifier list. Addons opt in by overriding
## [method SkillNodeAddon.get_tooltip_modifiers] (e.g. SkillDust lists its loot
## payload). Addons that contribute nothing are skipped.
func get_addon_tooltip_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in get_addons():
		var mods := a.get_tooltip_modifiers()
		if mods.is_empty():
			continue
		out.append({"title": a.get_tooltip_title(), "modifiers": mods})
	return out


## Reset node combat health to full. Called on allocation (silent) and at
## turn-start upkeep (not silent — emits healed signal).
func refill(silent: bool = false) -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.restore_to_full()
	if not silent:
		var delta := hp.current - prev
		if delta > 0.0:
			healed.emit(delta, null)
			Events.skill_node_healed.emit(self, delta, null)


## Apply an incoming hit. Mitigation runs here so attackers don't need to know
## about defender stats; node soaks first, overflow eats core HP iff this is
## the owner's core node. Emits [signal damaged] (and re-emits on the global
## bus) so UI hooks fire even when 0 damage lands.
func take_damage(amount: float, source: Variant) -> void:
	if owned_by == null or amount <= 0.0:
		return
	var raw: DamageInstance
	if source is DamageInstance:
		raw = source
	else:
		raw = DamageInstance.new()
		raw.amount = amount
	var effective: float = Mitigation.apply(raw, owned_by.stat_board)
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var before := hp.current
	hp.deplete(effective)
	var soaked: float = before - hp.current
	damaged.emit(effective, source)
	Events.skill_node_damaged.emit(self, effective, source)
	var overflow: float = effective - soaked
	if owned_by.core_location == self:
		if overflow > 0.0 and owned_by.stat_board != null and owned_by.stat_board.health != null:
			owned_by.stat_board.health.deplete(overflow)
		return
	if hp.current <= 0.0:
		depleted.emit()
		Events.skill_node_depleted.emit(self)

## Restore HP by [param amount], clamped at max. Emits [signal healed] (and
## re-emits on the global bus) with the effective delta actually restored.
func heal_damage(amount: float, source: Variant) -> void:
	if owned_by == null or amount <= 0.0:
		return
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.set_current(min(hp.current + amount, hp.value))
	var effective := hp.current - prev
	if effective > 0.0:
		healed.emit(effective, source)
		Events.skill_node_healed.emit(self, effective, source)

# ── Internals ──────────────────────────────────────────────────────────────


func _refresh_hp_binding() -> void:
	# Detach from previous owner's node_health; attach to the new owner's.
	if _bound_entity_node_health != null and _bound_entity_node_health.value_changed.is_connected(_on_entity_node_health_changed):
		_bound_entity_node_health.value_changed.disconnect(_on_entity_node_health_changed)
		_bound_entity_node_health = null
	if owned_by != null and owned_by.stat_board != null:
		_init_node_board()
		_bound_entity_node_health = owned_by.stat_board.get_stat(&"node_health")
		if _bound_entity_node_health != null:
			if not _bound_entity_node_health.value_changed.is_connected(_on_entity_node_health_changed):
				_bound_entity_node_health.value_changed.connect(_on_entity_node_health_changed)
			# Sync our combat health pool's base_value to the entity baseline.
			_sync_combat_health_base()
		refill(true)
	else:
		_reset_combat_health()


func _on_entity_node_health_changed() -> void:
	_sync_combat_health_base()


func _sync_combat_health_base() -> void:
	if _bound_entity_node_health == null:
		return
	var hp := _ensure_local_stat(&"node_health") as PoolStat
	if hp == null:
		return
	hp.base_value = _bound_entity_node_health.get_value()


func _reset_combat_health() -> void:
	var hp := node_board.get_stat(&"node_health") as PoolStat if node_board != null else null
	if hp != null:
		hp.set_current(0.0)


func _init_node_board() -> void:
	if node_board == null:
		node_board = StatBoard.new()


func _refresh_alloc_count() -> void:
	if owned_by == null:
		alloc_count = 0
	elif alloc_count == 0:
		alloc_count = 1


# Addon plumbing. Carrier owns its `modifiers` array as the source-of-truth
# for AllocationSystem, so addons mutate it directly here (append/erase).
# While allocated we also push/pop live on the entity board so the effect
# is immediate — same StatModifier instance, no double-pop because
# AllocationSystem iterates the (now-updated) array on dealloc.
func _on_addon_added(c: Node) -> void:
	if not (c is SkillNodeAddon):
		return
	var a := c as SkillNodeAddon
	if a.unique:
		for existing in get_addons():
			if existing != a and existing.get_script() == a.get_script():
				push_error("Duplicate unique addon %s on %s; rejecting." % [a.get_script().resource_path, name])
				a.queue_free()
				return
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	for m in a.entity_modifiers:
		modifiers.append(m)
		if board != null:
			board.add_modifier(m)
	for m in a.local_modifiers:
		var s := _ensure_local_stat(m.stat_id)
		if not s.has_modifier(m):
			s.add_modifier(m)
	a.visible = not sensed
	_sync_visuals()


func _on_addon_removed(c: Node) -> void:
	if not (c is SkillNodeAddon):
		return
	var a := c as SkillNodeAddon
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	for m in a.entity_modifiers:
		modifiers.erase(m)
		if board != null:
			board.remove_modifier(m)
	for m in a.local_modifiers:
		var s: Stat = node_board.get_stat(m.stat_id) if node_board != null else null
		if s != null:
			s.remove_modifier(m)


## Core-movement slide-in (#21). Called on the *new* core slot after
## AllocationSystem.move_core commits; offsets the CoreMarker to start at
## the previous slot's world position and tweens it back to local zero so
## the star reads as gliding into place. The underlying `core_location` has
## already flipped (and CoreMarker.visible was refreshed) — this is purely
## the visual catch-up. No-op if the marker isn't ready or the offset is
## degenerate (same node, fog-hidden marker).
func play_core_slide_from(world_pos: Vector2, duration: float = 0.25) -> void:
	if not is_node_ready() or core_marker == null or not core_marker.visible:
		return
	var offset := world_pos - global_position
	if offset.is_zero_approx():
		return
	core_marker.position = offset
	var tw := create_tween()
	tw.tween_property(core_marker, "position", Vector2.ZERO, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Brief white pulse on the BaseCircle. Auto-runs on the `damaged` signal;
## also callable externally (FloatingNumberLayer triggers it on wound/heal
## events so the core flashes alongside the floater).
func play_hit_flash() -> void:
	if _base_circle == null:
		return
	if _hit_flash_tween != null:
		_hit_flash_tween.kill()
	# Tweens BaseCircle.flash_amount only — leaves visuals.modulate free for
	# other consumers (selection tint, status effects, etc.) without colliding.
	_base_circle.flash_amount = 1.0
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_base_circle, "flash_amount", 0.0, 0.25)


# ── Denial feedback (#89) ────────────────────────────────────────────────────
# Two registers for a rejected deallocation, driven by PlayerInputController:
# the nodes that WOULD be islanded pulse danger-red (blink_blocked); the node
# the player actually tried to drop gets a short "bzzt — no" shake (shake_denied).
#
# The red tint lands on `_base_circle` (the node body), NOT on `visuals` — the
# hover glow (HoverRing) is a child of `visuals`, so a `visuals.modulate` tint
# multiplied the glow down to near-black and read as "the glow vanished". Body
# tint keeps the hover register (a different visual meaning: "pointer is here")
# clean. The shake offsets `visuals.position` (edges anchor on the node root, so
# endpoints don't move); the hover glow is counter-translated to stay world-fixed
# — the pointer isn't shaking, so its feedback shouldn't either.

const _DENY_COLOR := Color(1.0, 0.3, 0.3)
const _BLINK_STEP := 0.11
const _SHAKE_TIME := 0.30
const _SHAKE_AMPLITUDE := 5.0


func _reset_feedback() -> void:
	for t in _feedback_tweens:
		if t != null and t.is_valid():
			t.kill()
	_feedback_tweens.clear()
	if visuals != null:
		visuals.position = Vector2.ZERO
	if hover_ring != null:
		hover_ring.position = Vector2.ZERO
	if _base_circle != null:
		_base_circle.modulate = Color.WHITE


## Danger-red pulse — marks a node that a denied deallocation would island (#89).
func blink_blocked() -> void:
	if not is_node_ready() or _base_circle == null:
		return
	_reset_feedback()
	var t := create_tween()
	for i in 2:
		t.tween_property(_base_circle, "modulate", _DENY_COLOR, _BLINK_STEP)
		t.tween_property(_base_circle, "modulate", Color.WHITE, _BLINK_STEP)
	_feedback_tweens.append(t)


## Short "bzzt — no" shake + red tint — the node the player tried but failed to
## deallocate (#89). Horizontal decaying jitter on the body; hover glow held put.
func shake_denied() -> void:
	if not is_node_ready() or visuals == null:
		return
	_reset_feedback()
	if _base_circle != null:
		_base_circle.modulate = _DENY_COLOR
		var tint := create_tween()
		tint.tween_property(_base_circle, "modulate", Color.WHITE, _SHAKE_TIME)
		_feedback_tweens.append(tint)
	var shake := create_tween()
	var amps := [1.0, -0.72, 0.5, -0.32, 0.16, 0.0]
	var step := _SHAKE_TIME / float(amps.size())
	for a in amps:
		var off := Vector2(a * _SHAKE_AMPLITUDE, 0.0)
		shake.tween_property(visuals, "position", off, step).set_trans(Tween.TRANS_SINE)
		if hover_ring != null:
			shake.parallel().tween_property(hover_ring, "position", -off, step).set_trans(Tween.TRANS_SINE)
	_feedback_tweens.append(shake)


func _on_mouse_entered() -> void:
	hover_ring.show()
	if not Engine.is_editor_hint():
		Events.skill_node_hovered.emit(self)


func _on_mouse_exited() -> void:
	hover_ring.hide()
	if not Engine.is_editor_hint():
		Events.skill_node_unhovered.emit()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				left_clicked.emit(self)
			MOUSE_BUTTON_RIGHT:
				right_clicked.emit(self)
