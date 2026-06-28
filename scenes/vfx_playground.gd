class_name VFXPlayground
extends Node2D

## Loops the three allocation VFX in isolation so you can eyeball / tune them
## without driving real combat. Builds a small graph in code:
##   - one solo node for alloc / dealloc / single-shatter demos
##   - a five-node chain for the cascade demo
##
## Doesn't wire AllocationSystem.allocate() — too much SP/adjacency
## bookkeeping for a demo. Drives AllocationVFX by directly emitting
## the signals it listens to. Owner colour comes from a dummy Entity.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _ALLOC_VFX_SCRIPT: Script = preload("res://ui/vfx/allocation_vfx.gd")
const _ALLOCATION_SYSTEM_SCRIPT: Script = preload("res://systems/allocation_system.gd")
const _BATTLE_SYSTEM_SCRIPT: Script = preload("res://systems/battle_system.gd")

const _OWNER_COLOR: Color = Color(0.4, 0.8, 1.0)

# Cycle pacing (seconds).
const _ALLOC_HOLD: float = 1.5      # how long an allocated node sits before next step
const _UNALLOC_HOLD: float = 0.8
const _LABEL_HOLD: float = 0.6
const _CASCADE_REARM: float = 1.4   # extra time after cascade for the ripple to finish

var _alloc_system: Node
var _battle_system: Node
var _vfx: Node2D
var _owner: Entity
var _solo: SkillNode
var _chain: Array[SkillNode] = []
var _status_label: Label


func _ready() -> void:
	_build_systems()
	_build_owner()
	_build_solo_node()
	_build_chain()
	_build_status_label()
	# Centre camera on the demo area.
	var cam := Camera2D.new()
	cam.position = Vector2(0, 0)
	add_child(cam)
	cam.make_current()
	_run_loop()


func _build_systems() -> void:
	_alloc_system = _ALLOCATION_SYSTEM_SCRIPT.new()
	_alloc_system.name = "AllocationSystem"
	add_child(_alloc_system)
	_battle_system = _BATTLE_SYSTEM_SCRIPT.new()
	_battle_system.name = "BattleSystem"
	add_child(_battle_system)
	_vfx = _ALLOC_VFX_SCRIPT.new()
	_vfx.name = "AllocationVFX"
	add_child(_vfx)
	_vfx.bind(_alloc_system, _battle_system)


func _build_owner() -> void:
	_owner = Entity.new()
	_owner.display_name = "DemoOwner"
	_owner.color = _OWNER_COLOR
	# Stat board / core_class not needed — VFX only reads .color.
	add_child(_owner)


func _build_solo_node() -> void:
	_solo = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_solo.position = Vector2(-240, 0)
	_solo.base_type_color = Color.DIM_GRAY
	add_child(_solo)


func _build_chain() -> void:
	# Horizontal chain of 5 nodes; we'll BFS from index 0 (the impact) so
	# the ripple travels left → right.
	var spacing := 80.0
	var origin := Vector2(40, 0)
	for i in 5:
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		n.position = origin + Vector2(spacing * float(i), 0)
		n.base_type_color = Color.DIM_GRAY
		add_child(n)
		_chain.append(n)


func _build_status_label() -> void:
	# CanvasLayer keeps the label fixed in viewport space regardless of zoom.
	var layer := CanvasLayer.new()
	add_child(layer)
	_status_label = Label.new()
	_status_label.position = Vector2(24, 24)
	_status_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_status_label)


# --- Loop --------------------------------------------------------------------

func _run_loop() -> void:
	while is_inside_tree():
		await _phase_alloc_dealloc()
		await _phase_alloc_shatter()
		await _phase_cascade()


func _phase_alloc_dealloc() -> void:
	_label("1/3  allocate  →  voluntary deallocate")
	await _sleep(_LABEL_HOLD)

	_label("allocate")
	_set_owner(_solo, _owner)
	_alloc_system.allocated.emit(_solo, _owner, false)
	await _sleep(_ALLOC_HOLD)

	_label("voluntary deallocate (lift + holy puff)")
	_set_owner(_solo, null)
	_alloc_system.deallocated.emit(_solo, _owner)
	await _sleep(_UNALLOC_HOLD)


func _phase_alloc_shatter() -> void:
	_label("2/3  allocate  →  force-deallocate (single shatter)")
	await _sleep(_LABEL_HOLD)

	_label("allocate")
	_set_owner(_solo, _owner)
	_alloc_system.allocated.emit(_solo, _owner, false)
	await _sleep(_ALLOC_HOLD)

	_label("force-deallocate")
	_set_owner(_solo, null)
	_alloc_system.force_deallocated.emit(_solo, _owner)
	await _sleep(_UNALLOC_HOLD + 0.4)  # let shatter finish before next phase


func _phase_cascade() -> void:
	_label("3/3  cascade  —  allocate chain  →  shatter from impact outward")
	await _sleep(_LABEL_HOLD)

	# Allocate the whole chain.
	for n in _chain:
		_set_owner(n, _owner)
		_alloc_system.allocated.emit(n, _owner, false)
		await _sleep(0.08)
	await _sleep(_ALLOC_HOLD)

	# Cascade: BFS layers from chain[0] (the impact). Linear chain → one
	# node per layer, so the ripple reads as a clean left-to-right wave.
	_label("cascade!  impact = leftmost chain node")
	var layers: Array = []
	for n in _chain:
		var layer: Array[SkillNode] = [n]
		layers.append(layer)
	# Emit cascade_started BEFORE clearing owners — VFX snapshots the
	# owner colour from the defender arg, but it's good hygiene either way.
	_battle_system.cascade_started.emit(layers, _owner)
	# Emit per-node force_deallocated to clear AllocationVFX._cascade_scheduled
	# (otherwise the dict accumulates entries across loop iterations).
	for n in _chain:
		_set_owner(n, null)
		_alloc_system.force_deallocated.emit(n, _owner)

	await _sleep(_CASCADE_REARM)


# --- Helpers -----------------------------------------------------------------

func _set_owner(node: SkillNode, entity: Entity) -> void:
	# SkillNode.owned_by drives the fill-circle visual via owner_changed.
	node.owned_by = entity


func _label(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
