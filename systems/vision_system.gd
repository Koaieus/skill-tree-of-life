@tool
class_name VisionSystem
extends Node

## Computes per-frame visibility + sensor reach over the graph from one or
## more viewer entities. Pure data: no rendering. Two consumers wire in:
##
##  - [b]Input gating[/b]: on every recompute, toggles [member SkillNode.input_pickable]
##    so non-visible nodes can't be hovered, clicked, or queried by spells.
##    Tooltip suppression falls out of mouse_entered never firing.
##  - [b]FogOverlay[/b]: reads [method get_vision_sources] to render the
##    darkness mask. Sensed-only nodes are queryable via [method is_sensed]
##    but get no fog cutout (renderer's choice how to depict them).
##
## Sources of vision: every node owned by a viewer contributes a circle at
## its global_position with radius = that node's local vision_range
## (entity stat × node-local mods composed via LocalStat). Per-node so
## addons like a Spyglass can buff sight on one node only.
##
## Sources of sensor: BFS up to [code]viewer.stat_board.sensor_range[/code]
## hops from each owned node through the graph edges. Sensed ∖ visible
## = "blip with no detail" set.
##
## [b]Composability[/b]:
##   - Remove this node from the scene → no recomputes, input_pickable stays
##     true everywhere, no fog. Fully disabled.
##   - [member viewers] empty + [member empty_mode] = OFF → all nodes marked
##     visible (system inert but still wired).
##   - empty + DARKNESS → nothing visible.
##   - empty + ALL_ENTITIES → effective viewers = group("entities") members.

enum EmptyMode {
	OFF,            ## All nodes considered visible. The "off switch".
	DARKNESS,       ## Nothing visible. Pure fog.
	ALL_ENTITIES,   ## Use every Entity in group("entities") as a viewer.
}

## Logical visibility change — fires on _recompute (allocation, stat
## change, empty-mode toggle). Drives input_pickable + render-mode hide.
signal visibility_changed

## Per-frame render tick — fires while any circle is animating toward its
## target radius. FogOverlay re-uploads uniforms on each tick.
signal vision_render_tick

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var viewers: Array[Entity] = []:
	set(value):
		viewers = value
		if is_inside_tree():
			_rebind_viewers()
			_recompute()
@export var empty_mode: EmptyMode = EmptyMode.OFF:
	set(value):
		empty_mode = value
		if is_inside_tree():
			_rebind_viewers()
			_recompute()
## Lerp rate for circle radius animation. Higher = snappier. ~8 gives a
## ~90ms 90%-complete fade; 0 disables animation (instant snap).
@export_range(0.0, 30.0, 0.1) var ease_rate: float = 8.0

# Sub-pixel cleanup threshold. Retreating circles snap to 0 once they get
# within this radius. Not exposed because the snap-to-target at < 0.5
# already makes this effectively invisible to gameplay tuning.
const _RETIRE_RADIUS := 1.0

# Per-viewer Stat connections (entity-side vision/sensor) and per-node
# LocalStat connections (node-side vision overrides via addons). Rebuilt
# eagerly on every recompute — cheap, no leak from stale owners.
var _bound_entity_stats: Array[Stat] = []
var _bound_local_stats: Array[LocalStat] = []

var _visible: Dictionary = {}   # SkillNode → true (logical)
var _sensed: Dictionary = {}    # SkillNode → true (logical)
# Per-source animation state. SkillNode → { radius: float, target: float }.
# `radius` is the rendered radius (lerped); `target` is the logical
# vision_range. Entries with target=0 retreat to 0 then get dropped.
var _circles: Dictionary = {}


func _ready() -> void:
	# Signal wiring is runtime-only — allocation/graph mutate only at play
	# time. In editor we still recompute on _ready so the fog repaints
	# whenever the scene is reloaded; setters drive subsequent updates.
	if not Engine.is_editor_hint():
		if allocation_system != null:
			allocation_system.allocated.connect(_on_allocation_changed.unbind(2))
			allocation_system.deallocated.connect(_on_allocation_changed.unbind(2))
		if graph != null:
			graph.node_added.connect(_on_allocation_changed.unbind(1))
			graph.node_removed.connect(_on_allocation_changed.unbind(1))
	_rebind_viewers()
	_recompute.call_deferred()


func is_visible(node: SkillNode) -> bool:
	return _visible.has(node)


func is_sensed(node: SkillNode) -> bool:
	return _sensed.has(node)


## For renderers. Each entry: { pos: Vector2 (world), radius: float,
## motion: float (0..1) }. `radius` is the rendered (animated) radius,
## not the logical target — stale entries from deallocated sources stay
## until their fade completes. `motion` is non-zero while the circle is
## still moving toward target, used by the shader for frontier glow.
func get_vision_sources() -> Array:
	var out: Array = []
	for k in _circles:
		if not is_instance_valid(k):
			continue
		var e: Dictionary = _circles[k]
		if e.radius <= 0.0:
			continue
		out.append({
			"pos": (k as SkillNode).global_position,
			"radius": e.radius,
			"motion": e.get("motion", 0.0),
		})
	return out


## Whether the FogOverlay should be drawn at all. False when the system
## is in its inert "all visible" state — saves a fullscreen fragment pass
## and avoids the shader's "zero circles → fully dark" default kicking in
## as a confusing artifact.
func should_render_fog() -> bool:
	if not viewers.is_empty():
		return true
	return empty_mode != EmptyMode.OFF


## Entities currently treated as viewers given the explicit list and the
## empty-mode policy. Empty list + ALL_ENTITIES → group sweep.
func _effective_viewers() -> Array[Entity]:
	if viewers != null and not viewers.is_empty():
		var out: Array[Entity] = []
		for v in viewers:
			if v != null:
				out.append(v)
		return out
	if is_inside_tree() and empty_mode == EmptyMode.ALL_ENTITIES:
		var out: Array[Entity] = []
		for n in get_tree().get_nodes_in_group(&"entities"):
			if n is Entity:
				out.append(n)
		return out
	return []


func _on_allocation_changed() -> void:
	_rebind_viewers()
	_recompute()


func _rebind_viewers() -> void:
	for s in _bound_entity_stats:
		if is_instance_valid(s) and s.value_changed.is_connected(_recompute):
			s.value_changed.disconnect(_recompute)
	_bound_entity_stats.clear()
	for v in _effective_viewers():
		if v.stat_board == null:
			continue
		_bind_entity_stat(v.stat_board.get_stat(&"vision_range"))
		_bind_entity_stat(v.stat_board.get_stat(&"sensor_range"))


func _bind_entity_stat(s: Stat) -> void:
	if s == null:
		return
	if not s.value_changed.is_connected(_recompute):
		s.value_changed.connect(_recompute)
	_bound_entity_stats.append(s)


func _rebind_local_stats(owner_nodes: Array) -> void:
	for ls in _bound_local_stats:
		if is_instance_valid(ls) and ls.value_changed.is_connected(_recompute):
			ls.value_changed.disconnect(_recompute)
	_bound_local_stats.clear()
	for n in owner_nodes:
		var ls := (n as SkillNode).get_local_stat(&"vision_range")
		if ls != null:
			ls.value_changed.connect(_recompute)
			_bound_local_stats.append(ls)


func _recompute() -> void:
	if graph == null:
		return
	_visible.clear()
	_sensed.clear()

	var nodes := graph.get_skill_nodes()
	var effective := _effective_viewers()

	# Mark all existing circles as retreating; the active loop below
	# overwrites targets for sources that are still owned. Sources that
	# silently dropped (deallocation, viewer removed) stay in _circles
	# with target=0 so they animate out instead of popping.
	for k in _circles:
		_circles[k].target = 0.0

	if effective.is_empty():
		match empty_mode:
			EmptyMode.OFF:
				for n in nodes:
					_visible[n] = true
			EmptyMode.DARKNESS, EmptyMode.ALL_ENTITIES:
				pass
	else:
		var owned_per_viewer: Dictionary = {}
		for n in nodes:
			var owner: Entity = n.owned_by
			if owner != null and owner in effective:
				if not owned_per_viewer.has(owner):
					owned_per_viewer[owner] = []
				owned_per_viewer[owner].append(n)

		# Logical visibility uses TARGET radii, not animated. Targeting and
		# input gating snap on allocation; only the render fades.
		var all_owned: Array = []
		var targets: Array = []  # parallel to all_owned; the target radius for each
		for viewer in effective:
			for own_node in owned_per_viewer.get(viewer, []):
				all_owned.append(own_node)
				var ls := (own_node as SkillNode).get_local_stat(&"vision_range")
				var r: float = float(ls.value) if ls != null else 0.0
				targets.append(r)
				if not _circles.has(own_node):
					_circles[own_node] = {"radius": 0.0, "target": r}
				else:
					_circles[own_node].target = r

		for n in nodes:
			for i in all_owned.size():
				var src: SkillNode = all_owned[i]
				var r: float = targets[i]
				var dx: float = n.global_position.x - src.global_position.x
				var dy: float = n.global_position.y - src.global_position.y
				if dx * dx + dy * dy <= r * r:
					_visible[n] = true
					break

		# Sensed: BFS hops through edges from owned nodes, capped per-viewer
		# at its sensor_range. Skips already-visible.
		for viewer in effective:
			var hops := 0
			if viewer.stat_board != null:
				var ss := viewer.stat_board.get_stat(&"sensor_range")
				if ss != null:
					hops = int(ss.value)
			if hops <= 0:
				continue
			var frontier: Dictionary = {}
			for n in owned_per_viewer.get(viewer, []):
				frontier[n] = true
			for _h in range(hops):
				var next: Dictionary = {}
				for n in frontier:
					for nb in graph.get_neighbours(n):
						if _visible.has(nb) or _sensed.has(nb):
							continue
						_sensed[nb] = true
						next[nb] = true
				if next.is_empty():
					break
				frontier = next

		_rebind_local_stats(all_owned)

	# Single lever for input gating. Non-visible nodes can't be hovered,
	# clicked, or hit by spell targeting — tooltip suppression falls out
	# of mouse_entered never firing.
	for n in nodes:
		n.input_pickable = _visible.has(n)

	# Set process state so the animation loop only runs when something
	# is actually moving. Cheap to toggle, saves a per-frame walk while idle.
	set_process(_has_pending_motion())

	visibility_changed.emit()


func _process(delta: float) -> void:
	if _circles.is_empty():
		set_process(false)
		return
	# Frame-rate-independent ease-out. ease_rate=0 → t=0 → no motion;
	# we still drop dead entries that already hit 0 in earlier frames.
	var t: float = 1.0 - exp(-ease_rate * delta) if ease_rate > 0.0 else 1.0
	var to_drop: Array = []
	var any_motion := false
	for k in _circles:
		var e: Dictionary = _circles[k]
		var r: float = e.radius
		var tgt: float = e.target
		if not is_equal_approx(r, tgt):
			r = lerp(r, tgt, t)
			# Snap to target when close enough so retreating circles
			# actually reach 0 (and exit) instead of asymptoting.
			if abs(r - tgt) < 0.5:
				r = tgt
			e.radius = r
			any_motion = true
		# Motion strength: how far this circle still is from its target,
		# normalized against a reference scale. Drives the frontier glow
		# in the shader. Decays naturally as r → tgt.
		var ref: float = max(tgt, _RETIRE_RADIUS * 2.0)
		e.motion = clamp(abs(r - tgt) / ref, 0.0, 1.0)
		if tgt == 0.0 and r <= _RETIRE_RADIUS:
			to_drop.append(k)
		if not is_instance_valid(k):
			to_drop.append(k)
	for k in to_drop:
		_circles.erase(k)
	if any_motion or not to_drop.is_empty():
		vision_render_tick.emit()
	if not _has_pending_motion():
		set_process(false)


func _has_pending_motion() -> bool:
	for k in _circles:
		var e: Dictionary = _circles[k]
		if not is_equal_approx(e.radius, e.target):
			return true
	return false
