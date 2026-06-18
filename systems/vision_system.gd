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

signal visibility_changed

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

# Per-viewer Stat connections (entity-side vision/sensor) and per-node
# LocalStat connections (node-side vision overrides via addons). Rebuilt
# eagerly on every recompute — cheap, no leak from stale owners.
var _bound_entity_stats: Array[Stat] = []
var _bound_local_stats: Array[LocalStat] = []

var _visible: Dictionary = {}        # SkillNode → true
var _sensed: Dictionary = {}         # SkillNode → true
var _vision_sources: Array = []      # [{pos: Vector2, radius: float}, ...]


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


## For renderers. Each entry: { pos: Vector2 (world), radius: float }.
func get_vision_sources() -> Array:
	return _vision_sources


## Entities currently treated as viewers given the explicit list and the
## empty-mode policy. Empty list + ALL_ENTITIES → group sweep.
func _effective_viewers() -> Array[Entity]:
	if viewers != null and not viewers.is_empty():
		var out: Array[Entity] = []
		for v in viewers:
			if v != null:
				out.append(v)
		return out
	if empty_mode == EmptyMode.ALL_ENTITIES:
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
	_vision_sources.clear()

	var nodes := graph.get_skill_nodes()
	var effective := _effective_viewers()

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

		# Visible: Euclidean radius from each owned node, radius read locally
		# so per-node mods (Spyglass etc) compose into the source-of-truth.
		var all_owned: Array = []
		for viewer in effective:
			for own_node in owned_per_viewer.get(viewer, []):
				all_owned.append(own_node)
				var ls := (own_node as SkillNode).get_local_stat(&"vision_range")
				var r: float = float(ls.value) if ls != null else 0.0
				_vision_sources.append({"pos": (own_node as SkillNode).global_position, "radius": r})

		for n in nodes:
			for src in _vision_sources:
				var dx: float = n.global_position.x - src.pos.x
				var dy: float = n.global_position.y - src.pos.y
				var r: float = src.radius
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

	visibility_changed.emit()
