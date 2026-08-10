@tool
class_name Graph
extends Node2D

## The battlefield. Holds SkillNodes (under `skill_nodes_container`) and Edges
## (under `edges_container`), plus a Navigator that mirrors structural state
## as an AStar view. Scenes built from this class are intended to be loaded
## as levels — procgen builds the contents, then the result is instanced
## under the game's level layer.
##
## Decoupling: Graph emits structural signals; Navigator, AllocationSystem,
## renderers, and AIs listen. Graph itself never reaches into the AStar or
## the entity stat boards.

signal node_added(skill_node: SkillNode)
signal node_removed(skill_node: SkillNode)
signal edge_added(edge: Edge)
signal edge_removed(edge: Edge)

## Where dynamically-spawned [Entity] instances live (procgen, scripted setup).
## Parallel to the other containers — Graph owns the slot, GameRoot owns the
## spawning API. Hand-authored entities (dev_sandbox) may live elsewhere; the
## `%Player` unique-name lookup ignores parent.

@onready var navigator: Navigator = $Navigator
@onready var entities_container: Node = $Entities
@onready var skill_nodes_container: Node2D = $Nodes
@onready var edges_container: Node2D = $Edges

## Shared multimesh every regular (non-self-loop) Edge draws through (#413) —
## one draw call, one z_index, no per-edge CanvasItem. Public (not `_edge_mesh`)
## so tests can assert against the real GPU-facing buffer directly instead of
## only Edge's own mirrored `render_*` fields — see
## test/unit/test_edge_mesh_render.gd.
@onready var edge_mesh: MultiMeshInstance2D = $EdgeMesh

# Edge → its instance index in `edge_mesh.multimesh`. Built fully in code
# (never authored in the .tscn): the multimesh buffer is per-instance RUNTIME
# state, not something a `.tscn`/`@export` should carry — see
# .claude/rules/gdscript-pitfalls.md. `_edge_slot_owner` is the reverse map,
# needed because removal is swap-with-last: the edge that gets moved into the
# freed slot must have its own `_edge_slot` entry corrected.
var _edge_slot: Dictionary[Edge, int] = {}
var _edge_slot_owner: Array[Edge] = []

## Allocated size of `edge_mesh.multimesh`'s GPU buffer — grown by doubling,
## never shrunk. See `_grow_edge_mesh_capacity`'s docstring for why this is
## kept separate from the live edge count.
var _edge_mesh_capacity: int = 0

# Topology index. Rebuilt lazily whenever either container gains or loses a
# child, so it stays correct for procgen, remove_skill_node, and any direct
# add_child. Not used in the editor: an inspector edit to `Edge.from` /
# `Edge.to` mutates topology without touching the child lists, and no editor
# path is hot enough to care.
var _nodes: Array[SkillNode] = []
var _edges: Array[Edge] = []
var _adjacency: Dictionary[SkillNode, Array] = {}
var _topology_dirty: bool = true


func _ready() -> void:
	_init_edge_mesh()
	edge_added.connect(_on_edge_added_render)
	edge_removed.connect(_on_edge_removed_render)
	for c: Node in [skill_nodes_container, edges_container]:
		c.child_entered_tree.connect(_mark_topology_dirty.unbind(1))
		c.child_exiting_tree.connect(_mark_topology_dirty.unbind(1))
	if Engine.is_editor_hint():
		return
	# Re-emit signals for content already authored into the scene so
	# late-bound listeners (Navigator, UI) can build their initial state
	# uniformly with the procgen-add-at-runtime path.
	for sn in get_skill_nodes():
		node_added.emit(sn)
	for e in get_edges():
		edge_added.emit(e)


## Fresh `MultiMesh` every `_ready()` (editor and runtime both) — the buffer
## is pure runtime state, never serialized, so there's nothing to preserve
## across a reload. One unit `QuadMesh`; per-instance transform stretches it
## along the segment, the shader (`graph/edge_mesh.gdshader`) expands it
## perpendicular to a screen-constant width at draw time.
func _init_edge_mesh() -> void:
	if edge_mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = 0
	mm.visible_instance_count = 0
	edge_mesh.multimesh = mm
	_edge_slot.clear()
	_edge_slot_owner.clear()
	_edge_mesh_capacity = 0


## Registers a freshly added [Edge] with its render target — every edge gets
## `bind_render_target` (so its `_push_transform`/`_push_colors` calls have
## somewhere to go) whether or not it ends up with a mesh slot; self-loops
## deliberately never get one (out of scope, #413 — they stay on their own
## `_draw()` path) and are skipped here.
func _on_edge_added_render(edge: Edge) -> void:
	edge.bind_render_target(self)
	if edge.is_self_loop:
		return
	_register_edge_slot(edge)
	edge.push_render_state()


func _on_edge_removed_render(edge: Edge) -> void:
	_unregister_edge_slot(edge)


func _register_edge_slot(edge: Edge) -> void:
	if _edge_slot.has(edge):
		return
	var idx := _edge_slot_owner.size()
	_edge_slot_owner.append(edge)
	_edge_slot[edge] = idx
	_grow_edge_mesh_capacity(_edge_slot_owner.size())
	edge_mesh.multimesh.visible_instance_count = _edge_slot_owner.size()


## Swap-with-last removal: the edge that WAS at the last slot moves into the
## freed one, so its buffer entry (transform + colors) must be copied down
## and its own `_edge_slot` entry corrected to the new index.
func _unregister_edge_slot(edge: Edge) -> void:
	var idx: int = _edge_slot.get(edge, -1)
	if idx == -1:
		return
	var last_idx := _edge_slot_owner.size() - 1
	if idx != last_idx:
		var moved := _edge_slot_owner[last_idx]
		_edge_slot_owner[idx] = moved
		_edge_slot[moved] = idx
		var mm := edge_mesh.multimesh
		mm.set_instance_transform_2d(idx, mm.get_instance_transform_2d(last_idx))
		mm.set_instance_color(idx, mm.get_instance_color(last_idx))
		mm.set_instance_custom_data(idx, mm.get_instance_custom_data(last_idx))
	_edge_slot_owner.remove_at(last_idx)
	_edge_slot.erase(edge)
	edge_mesh.multimesh.visible_instance_count = _edge_slot_owner.size()


## `MultiMesh.instance_count` reallocates the GPU-side instance buffer and
## silently DISCARDS every previously-written transform/color/custom-data on
## ANY write — confirmed against a real (opengl3) renderer. Godot's headless
## dummy driver no-ops the whole per-instance read/write path instead of
## reproducing this, which is exactly why `_register_edge_slot` bumping
## `instance_count` once per edge (the pre-fix code) sailed through every
## headless probe and `mise run test` while silently zeroing out every
## edge's transform except the most recently added one — the actual cause of
## edges rendering invisible after #413, not the shader math a prior
## diagnosis pass suspected (see docs/handoffs/edge-mesh-invisible.md).
##
## Fix: `instance_count` (buffer capacity) is grown by doubling here, rare
## enough to afford repopulating every already-registered edge's slot from
## its own `Edge.render_*` mirrors (always kept in sync locally, independent
## of the GPU buffer) right after the reallocation. Day-to-day add/remove
## instead move `visible_instance_count` — draw-range only, never
## reallocates, never touches slots the buffer isn't discarding.
func _grow_edge_mesh_capacity(min_count: int) -> void:
	if min_count <= _edge_mesh_capacity:
		return
	var mm := edge_mesh.multimesh
	_edge_mesh_capacity = maxi(min_count, maxi(_edge_mesh_capacity * 2, 8))
	mm.instance_count = _edge_mesh_capacity
	for i in range(_edge_slot_owner.size()):
		var e := _edge_slot_owner[i]
		mm.set_instance_transform_2d(i, e.render_transform)
		var packed := e.render_color_b
		packed.a = e.render_vis_state
		mm.set_instance_color(i, e.render_color_a)
		mm.set_instance_custom_data(i, packed)


## Called by [Edge] whenever its segment/endpoints change. No-op if `edge`
## has no slot (self-loop, or not yet registered).
func set_edge_transform(edge: Edge, xform: Transform2D) -> void:
	var idx: int = _edge_slot.get(edge, -1)
	if idx == -1:
		return
	edge_mesh.multimesh.set_instance_transform_2d(idx, xform)


## Called by [Edge] whenever its lit/sensed/vision-visible state changes.
## `color_a`/`color_b` are the two endpoints' display colours (HDR lift
## baked in); `vis_state` is one of [constant Edge.VIS_HIDDEN] /
## [constant Edge.VIS_VISIBLE] / [constant Edge.VIS_SENSED], packed into the
## otherwise-redundant alpha of the custom-data channel — see
## `graph/edge_mesh.gdshader`'s header comment for the full packing.
func set_edge_colors(edge: Edge, color_a: Color, color_b: Color, vis_state: float) -> void:
	var idx: int = _edge_slot.get(edge, -1)
	if idx == -1:
		return
	var mm := edge_mesh.multimesh
	mm.set_instance_color(idx, color_a)
	var packed := color_b
	packed.a = vis_state
	mm.set_instance_custom_data(idx, packed)


## Every [SkillNode] in the graph. Returns a private copy — callers may mutate
## it (the spell playground appends the caster's node to the result).
func get_skill_nodes() -> Array[SkillNode]:
	if skill_nodes_container == null:
		return [] as Array[SkillNode]
	_ensure_topology()
	return _nodes.duplicate()


## Every [Edge] in the graph. Returns a private copy — see [method get_skill_nodes].
func get_edges() -> Array[Edge]:
	if edges_container == null:
		return [] as Array[Edge]
	_ensure_topology()
	return _edges.duplicate()


## Direct neighbours of [param node] — every other endpoint that shares an
## edge with it. Reads a cached adjacency index, no AStar dependency, so it
## works in editor context (spell playground, validation).
##
## Hot path: the vision system's sensed traversal calls this once per pop, so
## it must not be O(edges). Returns a fresh array — callers may mutate it.
func get_neighbours(node: SkillNode) -> Array[SkillNode]:
	if edges_container == null or node == null:
		return [] as Array[SkillNode]
	_ensure_topology()
	var adj: Array = _adjacency.get(node, [])
	return adj.duplicate()


func _mark_topology_dirty() -> void:
	_topology_dirty = true


## Rebuild the node list, edge list, and adjacency index from the containers.
##
## Always rebuilds in the editor: an inspector edit to `Edge.from` / `Edge.to`
## re-points an edge without touching either container's child list, so the
## dirty flag would never fire. No editor path is hot enough to care.
func _ensure_topology() -> void:
	if skill_nodes_container == null or edges_container == null:
		return
	if not _topology_dirty and not Engine.is_editor_hint():
		return
	_topology_dirty = false

	_nodes = []
	for c in skill_nodes_container.get_children():
		if c is SkillNode:
			_nodes.append(c)
	_edges = []
	for c in edges_container.get_children():
		if c is Edge:
			_edges.append(c)

	# One pass over the edges, appending each endpoint to the other's list.
	# Order within a node's list matches edge child order.
	_adjacency = {}
	for n in _nodes:
		_adjacency[n] = [] as Array[SkillNode]
	for e in _edges:
		if e.from == null or e.to == null:
			continue
		# Self-loop: per graph theory each endpoint counts independently, so a
		# single self-loop edge contributes the node itself twice (degree +2).
		# Consumers that BFS already dedupe via their own visited sets; this
		# keeps spell propagation (FanAllStep etc.) consistent with the
		# "self-loop weaponisable by SUM merger" mechanic. See Resonator.
		if e.from == e.to:
			if _adjacency.has(e.from):
				_adjacency[e.from].append(e.from)
				_adjacency[e.from].append(e.from)
			continue
		if _adjacency.has(e.from):
			_adjacency[e.from].append(e.to)
		if _adjacency.has(e.to):
			_adjacency[e.to].append(e.from)


func add_skill_node(node: SkillNode) -> void:
	skill_nodes_container.add_child(node)
	node_added.emit(node)


func remove_skill_node(node: SkillNode) -> void:
	# Connected edges removed first so the Navigator sees a consistent
	# graph state at every signal step.
	for e in get_edges():
		if e.from == node or e.to == node:
			remove_edge(e)
	skill_nodes_container.remove_child(node)
	node_removed.emit(node)
	node.queue_free()

const EDGE = preload("res://graph/edge.tscn")

func add_edge(from: SkillNode, to: SkillNode) -> Edge:
	var edge := EDGE.instantiate() as Edge
	edge.from = from
	edge.to = to
	edges_container.add_child(edge)
	edge_added.emit(edge)
	return edge


func remove_edge(edge: Edge) -> void:
	if edge.from != null:
		edge.from.self_loops.erase(edge)
	edges_container.remove_child(edge)
	edge_removed.emit(edge)
	edge.queue_free()
