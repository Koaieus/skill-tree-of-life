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
@export var modifiers: Array[StatModifierDef] = []

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()

@onready var visuals: Node2D = $Visuals
@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_marker: Node2D = $Visuals/CoreMarker

# Owner subscription tracking — re-bound whenever `owned_by` changes so the
# CoreMarker reflects the *current* owner's core_location, not a stale one.
var _bound_owner: Entity = null

## Ephemeral combat HP. Refills to [method get_max_hp] at the owning entity's
## turn start and on first allocation. Not in the stat-modifier pipeline — see
## docs/domain/node-hp.md for the reasoning + future-expansion path.
var current_hp: float = 0.0

# node_health stat subscription, kept in lockstep with `owned_by` so a max-HP
# change (level-up, modifier swap) clamps + refills `current_hp` immediately.
var _bound_node_health: Stat = null

# Hit-flash bookkeeping. Killed and re-created on every hit so back-to-back
# damage doesn't visually merge into one stuck red.
var _hit_flash_tween: Tween


func _ready() -> void:
	_sync_collision()
	owner_changed.connect(_refresh_core_marker)
	owner_changed.connect(_refresh_hp_binding)
	damaged.connect(_play_hit_flash.unbind(2))
	_refresh_core_marker()
	_refresh_hp_binding()


func _refresh_core_marker() -> void:
	if _bound_owner != owned_by:
		if _bound_owner != null and _bound_owner.core_location_changed.is_connected(_refresh_core_marker):
			_bound_owner.core_location_changed.disconnect(_refresh_core_marker)
		_bound_owner = owned_by
		if _bound_owner != null:
			_bound_owner.core_location_changed.connect(_refresh_core_marker)
	core_marker.visible = owned_by != null and owned_by.core_location == self


func _sync_collision() -> void:
	var collision := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var shape := collision.shape as CircleShape2D
	if shape == null:
		return
	shape.radius = radius


func is_allocated() -> bool:
	return owned_by != null


func is_core() -> bool:
	return owned_by != null and owned_by.core_location == self


func get_owner_color() -> Color:
	if owned_by:
		return owned_by.color
	return Color.WHITE


# ── Combat HP ──────────────────────────────────────────────────────────────

## Max HP for this node. Reads `node_health` off the owning entity's stat board.
## When node-local stats land, this graduates to a combining formula
## (see docs/domain/node-hp.md). 0 if unallocated.
func get_max_hp() -> float:
	if owned_by == null or owned_by.stat_board == null:
		return 0.0
	var v: Variant = owned_by.stat_board.get_value(&"node_health")
	return float(v) if v != null else 0.0


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


func _play_hit_flash() -> void:
	if visuals == null:
		return
	if _hit_flash_tween != null:
		_hit_flash_tween.kill()
	visuals.modulate = Color(1.0, 0.3, 0.3)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(visuals, "modulate", Color.WHITE, 0.25)


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
