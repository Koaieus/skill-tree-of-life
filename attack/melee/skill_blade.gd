@tool
class_name SkillBlade
extends Node2D

## Visual wrapper around a BladeState + BladeTrajectory. Owns the BladeNode
## and BladeEdge visuals; replays a trajectory by writing positions onto
## them frame-by-frame. Pure visuals — hit detection is the deterministic
## BladeHitScan over the trajectory, not Godot collision overlap.
##
## `@tool` because the melee sandbox tab (`addons/melee_sandbox/`) builds and
## swings real blades inside the editor. Nothing here auto-drives: a swing only
## happens when someone calls [method play], which keeps it on the live side of
## the "auto-tick = played; explicit-step = live" line
## (docs/domain/sandbox-framework.md).

## Emitted during non-ghost playback at the scheduled time of each hit event.
## hitter_idx is the particle or edge index; is_edge distinguishes the two.
signal hit(hitter_idx: int, is_edge: bool, target: SkillNode, t: float, damage: float)
signal playback_finished

const SCENE := preload("res://attack/melee/skill_blade.tscn")
const BLADE_NODE := preload("res://attack/melee/blade_node.tscn")
const BLADE_EDGE := preload("res://attack/melee/blade_edge.tscn")

@export var owned_by: Entity

## Look profile pushed onto every [BladeNode] / [BladeEdge] this blade spawns
## (#256). One resource per blade, so a sandbox can retune the whole swing live.
@export var style: BladeStyle = BladeNode.DEFAULT_STYLE:
	set(value):
		style = value
		_apply_style()

## The swing's pop outcome, set by the caller BEFORE [method play] when one is
## known ([member MeleeAttackPlan.last_pops]). Vertices it reports dead go
## [member BladeNode.disabled] at exactly the `t` they died — the interim "pop"
## look (#256). Null (the preview loop) means nothing ever de-lights.
##
## Read, never derived: the blade must not decide who died. That answer belongs
## to [BladePopResolver], which the same swing's `resolve()` already ran.
var pop_result: BladePopResolver.Result = null

## Mirror of [member MeleeAttackPlan.swing_cw]. Set by [MeleePreview] before
## [method simulate] so the live blade swings in the same direction the plan's
## resolve() simulated.
var swing_cw: bool = false

var state: BladeState
var trajectory: BladeTrajectory

var _node_visuals: Array[BladeNode] = []
var _edge_visuals: Array[BladeEdge] = []
var _nodes_container: Node2D
var _edges_container: Node2D
var _active_tween: Tween


func _ready() -> void:
	_edges_container = get_node_or_null("Edges")
	if _edges_container == null:
		_edges_container = Node2D.new()
		_edges_container.name = "Edges"
		add_child(_edges_container)
	_nodes_container = get_node_or_null("Nodes")
	if _nodes_container == null:
		_nodes_container = Node2D.new()
		_nodes_container.name = "Nodes"
		add_child(_nodes_container)


## True when the selected node set can form a valid blade.
static func is_valid_selection(
		skill_nodes: Array,
		pivot: SkillNode,
		induced_edges: Array) -> bool:
	return skill_nodes.size() >= 2 \
			and pivot in skill_nodes \
			and induced_edges.size() >= 1


## Construct the blade from a 1:1 copy of the chosen SkillNodes.
## `induced_edges`: Array of [SkillNode, SkillNode] pairs (induced subgraph).
## Call after adding the SkillBlade to the scene tree; safe to call again to
## rebuild for an updated selection (visuals are torn down + rebuilt).
func build_from_skill_nodes(
		skill_nodes: Array[SkillNode],
		pivot: SkillNode,
		induced_edges: Array,
		owner_entity: Entity) -> void:
	owned_by = owner_entity
	# A rebuild is a fresh blade: last swing's deaths must not de-light it.
	pop_result = null
	_clear_visuals()
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	var pivot_idx := 0
	var sn_to_idx: Dictionary = {}
	for i in skill_nodes.size():
		var sn := skill_nodes[i]
		sn_to_idx[sn] = i
		positions.append(sn.global_position)
		radii.append(sn.radius)
		if sn == pivot:
			pivot_idx = i
	var edges_idx: Array[Vector2i] = []
	for pair in induced_edges:
		edges_idx.append(Vector2i(sn_to_idx[pair[0]], sn_to_idx[pair[1]]))
	state = BladeState.build(positions, pivot_idx, edges_idx, radii)
	# Per-vertex damage is the node's own blade_damage (wielder base merged with
	# any node-local spike modifier) — one localized read per source node.
	for i in skill_nodes.size():
		state.vertex_damage[i] = skill_nodes[i].get_local_value(&"blade_damage")
	# Dispatch to addons after BladeState is built so they can append
	# constraints (Clamp's phantom brace). SkillBlade never learns specific
	# addon types — pure virtual dispatch.
	for i in skill_nodes.size():
		for addon in skill_nodes[i].get_addons():
			addon.apply_to_blade(state, i)
	_spawn_visuals()


## Run a swing simulation around the pivot. Returns a fresh trajectory each
## call; safe to invoke repeatedly (state is reset to the descriptor's
## original positions internally via re-build_from_skill_nodes if needed).
## Drivers are auto-built: one BladeArcDriver per pivot-adjacent particle.
func simulate(
		duration: float = 1.2,
		dt: float = BladeSim.DEFAULT_DT,
		iterations: int = BladeSim.DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0) -> BladeTrajectory:
	var drivers := _build_swing_drivers(duration)
	trajectory = BladeSim.simulate(
			state, drivers, duration, dt, iterations, velocity_iter_ref)
	return trajectory


## Tween visual positions through the trajectory. Awaitable.
##   - ghostly=true: translucent modulate, no hit signals emitted
##   - hits: pre-scanned BladeHitEvents emitted at their scheduled t
func play(
		traj: BladeTrajectory,
		hits: Array[BladeHitEvent] = [],
		ghostly: bool = false) -> void:
	if traj == null or traj.samples.is_empty():
		playback_finished.emit()
		return
	modulate = Color(1.0, 1.0, 1.0, 0.35) if ghostly else Color.WHITE
	var pending: Array[BladeHitEvent] = hits.duplicate()
	var dur := traj.duration()
	var tween := create_tween()
	_active_tween = tween
	tween.tween_method(
			_apply_playback_frame.bind(traj, pending, ghostly),
			0.0, dur, dur)
	await tween.finished
	_active_tween = null
	playback_finished.emit()


func _apply_playback_frame(
		t: float,
		traj: BladeTrajectory,
		pending: Array[BladeHitEvent],
		ghostly: bool) -> void:
	var positions := traj.sample(t)
	for i in _node_visuals.size():
		if i < positions.size():
			_node_visuals[i].global_position = positions[i]
		if pop_result != null:
			_node_visuals[i].disabled = pop_result.is_dead(i, t)
	while not pending.is_empty() and pending[0].t <= t:
		var ev: BladeHitEvent = pending.pop_front()
		if not ghostly:
			# D-1 MVP: edges are inert. Skip emission entirely so no zero-damage
			# floaters or stat-tracking noise leaks through.
			if ev.is_edge_hit():
				continue
			var damage := state.vertex_damage[ev.particle_idx]
			hit.emit(ev.particle_idx, false, ev.target as SkillNode, ev.t, damage)


## Stop any in-flight playback. Emits playback_finished so awaiters wake up.
func stop() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null
		playback_finished.emit()


func _build_swing_drivers(duration: float) -> Array[BladeDriver]:
	var drivers: Array[BladeDriver] = []
	var pivot_pos := state.positions[state.pivot_index]
	var seen: Dictionary = {}
	var sweep := -TAU if swing_cw else TAU
	for e in state.edges:
		var other := -1
		if e.x == state.pivot_index:
			other = e.y
		elif e.y == state.pivot_index:
			other = e.x
		if other < 0 or seen.has(other):
			continue
		seen[other] = true
		var offset := state.positions[other] - pivot_pos
		drivers.append(BladeArcDriver.new(
				other, pivot_pos, offset.length(), offset.angle(),
				sweep, duration))
	return drivers


func _clear_visuals() -> void:
	for n in _node_visuals:
		n.queue_free()
	for e in _edge_visuals:
		e.queue_free()
	_node_visuals.clear()
	_edge_visuals.clear()


func _spawn_visuals() -> void:
	var tint := entity_tint()
	for i in state.positions.size():
		var bn := BLADE_NODE.instantiate() as BladeNode
		bn.radius = state.radii[i]
		bn.is_pivot = (i == state.pivot_index)
		bn.style = style
		bn.tint = tint
		_nodes_container.add_child(bn)
		bn.global_position = state.positions[i]
		_node_visuals.append(bn)
	for e in state.edges:
		var be := BLADE_EDGE.instantiate() as BladeEdge
		be.style = style
		be.tint = tint
		_edges_container.add_child(be)
		be.from = _node_visuals[e.x]
		be.to = _node_visuals[e.y]
		_edge_visuals.append(be)


## The wielder's identity colour, or transparent when the blade has no owner
## (headless fixtures) — [BladeStyle] reads that as "authored base only".
func entity_tint() -> Color:
	return owned_by.color if owned_by != null else Color.TRANSPARENT


## Re-push the style (and the tint that rides with it) onto live visuals, so a
## sandbox swapping the resource mid-swing repaints without a rebuild.
func _apply_style() -> void:
	var tint := entity_tint()
	for bn in _node_visuals:
		bn.style = style
		bn.tint = tint
	for be in _edge_visuals:
		be.style = style
		be.tint = tint


## The spawned vertex visuals, pivot included, in [BladeState] particle order —
## so the sandbox can force a vertex de-lit for look tuning without inventing a
## fake [BladePopResolver.Result].
func get_node_visuals() -> Array[BladeNode]:
	return _node_visuals
