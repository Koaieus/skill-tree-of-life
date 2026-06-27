@tool
class_name SkillNode
extends Area2D

signal radius_changed
signal owner_changed
signal left_clicked(skill_node: SkillNode)
signal right_clicked(skill_node: SkillNode)
## Emitted on every take_damage call (even at 0 effective). Local twin of
## [signal Events.skill_node_damaged]; subscribe locally for per-node reactions
## (hit-flash lives right here), globally on the bus for UI like floating numbers.
signal damaged(amount: float, source: Variant)
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

@onready var visuals: Node2D = $Visuals
@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_marker: Node2D = $Visuals/CoreMarker
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

## Ephemeral combat HP. Refills to [method get_max_hp] at the owning entity's
## turn start and on first allocation. Not in the stat-modifier pipeline — see
## docs/domain/node-hp.md for the reasoning + future-expansion path.
var current_hp: float = 0.0

## Per-node allocation cap. `alloc_cap_max` defaults to 1 (single allocation
## slot); raise by 1 per stake via the entity's `skill_points.stake(1)` action.
## `alloc_count` mirrors live allocation: 0 = unowned, 1 = baseline, 2+ = staked.
## Pure node-local — these are not Stats and must never be registered with
## an entity StatBoard. If you want to scale modifier contributions by the
## stake count, read it directly off the SkillNode.
var alloc_cap_max: int = 1
var alloc_count: int = 0

# node_health stat subscription, kept in lockstep with `owned_by` so a max-HP
# change (level-up, modifier swap) clamps + refills `current_hp` immediately.
var _bound_node_health: Stat = null

## Sparse, lazy LocalStat instances — one per stat_id that an addon (or
## anything else) has localized on this node. Each LocalStat is bound to
## the owning entity's same-id Stat (if any) so its read merges entity +
## local bins in one pipeline run; see local_stat.gd.
var _local_stats: Dictionary = {}  # StringName → LocalStat

# Hit-flash bookkeeping. Killed and re-created on every hit so back-to-back
# damage doesn't visually merge into one stuck red.
var _hit_flash_tween: Tween


func _ready() -> void:
	_sync_collision()
	_sync_visuals()
	radius_changed.connect(_sync_visuals)
	owner_changed.connect(_sync_visuals)
	owner_changed.connect(_refresh_core_marker)
	owner_changed.connect(_refresh_hp_binding)
	owner_changed.connect(_refresh_local_stat_bindings)
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
	core_marker.visible = (not sensed) and owned_by != null and owned_by.core_location == self


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
	z_index = 1001 if sensed else 0
	core_marker.visible = (not sensed) and owned_by != null and owned_by.core_location == self
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

## Max HP for this node. Routes through a per-node LocalStat so any addon
## (or other source) localizing `node_health` composes correctly with the
## entity-side value via one PoE pipeline run. 0 if unallocated.
func get_max_hp() -> float:
	if owned_by == null or owned_by.stat_board == null:
		return 0.0
	var v: Variant = get_local_stat(&"node_health").value
	return float(v) if v != null else 0.0


## Lazy materialization of a per-node Stat for `stat_id`. If the owning
## entity has the same-id stat, we bind to it so the LocalStat's read
## merges entity + local bins. Owner changes re-bind via
## _refresh_local_stat_bindings. If the entity board doesn't carry that
## stat (older hand-authored boards predating the stat's introduction),
## we still seed the LocalStat from StatRegistry's default so reads return
## something sensible instead of 0.
func get_local_stat(stat_id: StringName) -> LocalStat:
	if not _local_stats.has(stat_id):
		var ls := LocalStat.new()
		var src: Stat = null
		if owned_by != null and owned_by.stat_board != null:
			src = owned_by.stat_board.get_stat(stat_id)
		if src != null:
			ls.definition = src.definition
			ls.entity_stat = src
		else:
			var def: StatDef = StatRegistry.get_def(stat_id)
			if def != null:
				ls.definition = def
				ls.base_value = def.default_value
		_local_stats[stat_id] = ls
	return _local_stats[stat_id]


func get_addons() -> Array[SkillNodeAddon]:
	var out: Array[SkillNodeAddon] = []
	if _addon_anchor == null:
		return out
	for c in _addon_anchor.get_children():
		if c is SkillNodeAddon:
			out.append(c)
	return out


## Reset to full. Called on owner change and at turn-start upkeep.
func refill() -> void:
	current_hp = get_max_hp()


## Apply an incoming hit. Mitigation runs here so attackers don't need to know
## about defender stats; node soaks first, overflow eats core HP iff this is
## the owner's core node. Emits [signal damaged] (and re-emits on the global
## bus) so UI hooks fire even when 0 damage lands.
func take_damage(amount: float, source: Variant) -> void:
	if owned_by == null or amount <= 0.0:
		return
	var raw := DamageInstance.new()
	raw.amount = amount
	# For mitigation-pipeline shape; type/source carry forward if the caller
	# supplied a DamageInstance directly (we accept the looser float form too).
	if source is DamageInstance:
		raw = source
	var effective: float = Mitigation.apply(raw, owned_by.stat_board)
	var soak: float = min(effective, current_hp)
	current_hp -= soak
	damaged.emit(effective, source)
	Events.skill_node_damaged.emit(self, effective, source)
	var overflow: float = effective - soak
	if owned_by.core_location == self:
		# Core node: never deallocates; any overflow eats the entity's core HP.
		if overflow > 0.0 and owned_by.stat_board != null and owned_by.stat_board.health != null:
			owned_by.stat_board.health.deplete(overflow)
		return
	if current_hp <= 0.0:
		depleted.emit()
		Events.skill_node_depleted.emit(self)


# ── Internals ──────────────────────────────────────────────────────────────


func _refresh_hp_binding() -> void:
	# Unbind previous owner's node_health stat (if any) and bind the current
	# one. Kept in lockstep with `owned_by` so a +node_health modifier landing
	# mid-turn clamps / heals our `current_hp` immediately.
	if _bound_node_health != null and _bound_node_health.value_changed.is_connected(_on_max_hp_changed):
		_bound_node_health.value_changed.disconnect(_on_max_hp_changed)
		_bound_node_health = null
	if owned_by != null and owned_by.stat_board != null:
		_bound_node_health = owned_by.stat_board.get_stat(&"node_health")
		if _bound_node_health != null and not _bound_node_health.value_changed.is_connected(_on_max_hp_changed):
			_bound_node_health.value_changed.connect(_on_max_hp_changed)
		refill()
	else:
		current_hp = 0.0


func _on_max_hp_changed() -> void:
	var cap := get_max_hp()
	if current_hp > cap:
		current_hp = cap


# Re-bind every materialized LocalStat to the current owner's same-id Stat.
# Unallocated → entity_stat = null and the local stat acts standalone.
## On allocate: count moves to 1 (the baseline slot). On dealloc: back to 0.
## Stakes (count > 1) are not auto-cleared on dealloc — extracting first is
## the player's responsibility, otherwise the staked SP heals via the future
## extract action. (Force-dealloc semantics for staked nodes: still open;
## design doc.)
func _refresh_alloc_count() -> void:
	if owned_by == null:
		alloc_count = 0
	elif alloc_count == 0:
		alloc_count = 1


func _refresh_local_stat_bindings() -> void:
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	for stat_id in _local_stats:
		var ls: LocalStat = _local_stats[stat_id]
		var src: Stat = board.get_stat(stat_id) if board != null else null
		if src != null and ls.definition == null:
			ls.definition = src.definition
		ls.entity_stat = src


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
		get_local_stat(m.stat_id).add_modifier(m)
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
		if _local_stats.has(m.stat_id):
			_local_stats[m.stat_id].remove_modifier(m)


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
