@tool
class_name FrontmatterRoot
extends Node2D

## The frontmatter shell: builds the menu tree once, then navigates it by moving
## the camera (#570).
##
## [b]One persistent graph. Nodes never move. The camera does.[/b] Every view is
## built at its [method FrontmatterLayout.solve] home and stays parented where it
## was put, at the z-index it was put at, for the life of the scene. The design
## canvas's `_select()` lifts the clicked node into a `transit` layer at
## `z-index: 15` while the hero fades out — the owner vetoed that in as many
## words ([i]"a big nope"[/i]), and this file is the shape of the veto:
## [method navigation_state] is a pure function of [member focus_id], so a
## forward-and-back traversal provably lands every view exactly where it started.
##
## [b]Grow, don't cut.[/b] A node's children rest COLLAPSED — stacked tight on
## their parent at [constant FrontmatterLayout.PREVIEW_SCALE] — and grow out to
## their homes when that parent takes the focus. The collapsed position is
## canonical, not a hover-only trick: it is where those children are whenever
## their parent is not the focus, which is also what makes back navigation
## symmetric for free. Both the camera travel and the sprout ride ONE `t`
## ([method set_progress]), so they are one motion rather than two that overlap.
##
## [b]Edges never pop.[/b] Every frame of a transition re-pushes both endpoints
## of every edge from the live view positions. No edge is ever reparented or
## rebuilt mid-transition — there is no code path here that could.
##
## [b]Panels are reached through the seam only.[/b] Routing a leaf calls
## [method FrontmatterPanels.show_panel]; this file knows nothing else about what
## a panel is. #573 fills them in, and an id whose panel has not landed yet is a
## documented no-op, so an unfinished panel leaves the graph on screen rather
## than erroring.

const _NODE_VIEW := preload("res://ui/frontmatter/menu_node_view.tscn")
const _EDGE_VIEW := preload("res://ui/frontmatter/menu_edge_view.tscn")

## Emitted once the camera has settled on a new focus. #574/#576 hang off this.
signal focus_changed(id: StringName)

## Seconds a full navigation takes: the camera travel and the sprout together.
## #567's table gives 850ms for hero travel; the sprout rides the same clock
## with a snappier curve rather than a duration of its own.
@export_range(0.0, 3.0, 0.01) var travel_duration: float = 0.85

## Skip every transition — jump straight to `set_progress(1.0)`.
##
## [method build] overwrites this from [member GameSettings.reduce_motion], so
## what is authored on the node is the default a run without the autoload gets
## (the editor, and #578's live tab). See [method _resolve_reduce_motion].
@export var reduce_motion: bool = false

var tree: MenuGraph = null
var camera: FrontmatterCamera = null

## Where the menu is. Written by [method focus]; the whole rest of the visible
## state is derived from it.
var focus_id: StringName = &""

var _views: Dictionary = {}
var _edges: Dictionary = {}
var _from_pose: Dictionary = {}
var _to_pose: Dictionary = {}
var _progress: float = 1.0
var _routed_panel: StringName = &""
var _settled: bool = false
var _transition: Tween = null

@onready var _camera_2d: Camera2D = %Camera
@onready var _graph_layer: Node2D = %GraphLayer
@onready var _panel_layer: CanvasLayer = %PanelLayer


func _ready() -> void:
	build()


## Builds the whole menu — every node view, every edge view, the camera — and
## parks the camera on the root. Idempotent: a rebuild clears what it made
## first, so #578's live tab can retune geometry and rebuild in place.
func build(menu_tree: MenuGraph = null) -> void:
	tree = menu_tree if menu_tree != null else MenuGraph.build()
	reduce_motion = _resolve_reduce_motion()
	_clear()
	_build_views()
	_build_edges()
	camera = FrontmatterCamera.new(_camera_2d, tree)
	_connect_panels()
	focus(tree.root, true)


## Navigates to [param id]. [param instant] (or [member reduce_motion]) lands it
## in one frame; otherwise a [Tween] drives [method set_progress] across
## [member travel_duration].
##
## The tween lives HERE and nowhere else: `set_progress(t)` with one external
## caller owning the clock is the repo's convention for an animated unit
## (`ui/tooltip_fan/addon_item.gd`), and it is what lets a test assert `t == 0`
## and `t == 1` without chasing frames.
func focus(id: StringName, instant: bool = false) -> void:
	if not tree.has(id):
		return
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
	focus_id = id
	_routed_panel = &""
	_settled = false
	_sync_allocation()
	_capture_transition()
	camera.travel_to(id)
	if instant or reduce_motion or travel_duration <= 0.0:
		set_progress(1.0)
		return
	set_progress(0.0)
	_transition = create_tween()
	_transition.tween_method(set_progress, 0.0, 1.0, travel_duration)


## Up one level. A no-op at the root — there is nowhere above it, and the menu
## must not empty itself out from under the player.
##
## [b]This is [method focus] with the parent's id, deliberately.[/b] The motion
## notes list "back-navigation doesn't mirror forward navigation" as a gap; under
## a camera there is nothing to mirror. Do not add a reverse path here.
func back() -> bool:
	var parent := tree.parent_of(focus_id)
	if parent == &"":
		return false
	var panels := _panels()
	if panels != null:
		panels.hide_all()
	focus(parent)
	return true


## Applies the whole transition at clock position `t` (0..1) — the camera, every
## sprouting child, and every edge, off ONE clock.
func set_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	camera.set_progress(_progress)
	var eased := FrontmatterCamera.ease_sprout(_progress)
	for id in _views:
		var view: MenuNodeView = _views[id]
		var from: Array = _from_pose[id]
		var to: Array = _to_pose[id]
		view.position = (from[0] as Vector2).lerp(to[0] as Vector2, eased)
		var s: float = lerpf(from[1] as float, to[1] as float, eased)
		view.scale = Vector2(s, s)
	_push_edges()
	if _progress >= 1.0 and not _settled:
		_settled = true
		_route_focus_panel()
		focus_changed.emit(focus_id)


## Everything a caller can see about where the menu is, as one comparable value.
##
## This exists for the anti-detaching guarantee: it is a pure function of
## [member focus_id], so "forward then back returns the exact prior state" is one
## equality rather than a list of spot checks — and any future change that made a
## view's pose depend on HOW it got there would fail it.
func navigation_state() -> Dictionary:
	var poses: Dictionary = {}
	for id in _views:
		var view: MenuNodeView = _views[id]
		poses[id] = [view.position, view.scale, view.allocated, view.get_parent(), view.z_index]
	var panels := _panels()
	return {
		&"focus": focus_id,
		&"camera": camera.current_transform(),
		&"poses": poses,
		&"panel": panels.shown_panel if panels != null else &"",
	}


## The view for a menu id, for #571/#574/#576 to reach without walking children.
func view_for(id: StringName) -> MenuNodeView:
	return _views.get(id) as MenuNodeView


## Ids on the path from the root to the current focus, root first.
func focus_path() -> Array[StringName]:
	return tree.path_to(focus_id)


func _panels() -> FrontmatterPanels:
	if _panel_layer == null:
		return null
	for child in _panel_layer.get_children():
		if child is FrontmatterPanels:
			return child as FrontmatterPanels
	return null


## The exit confirm asks; the SHELL quits. A panel that called
## `get_tree().quit()` itself would end the process the moment a test pressed its
## button, which is exactly why C1's routing-parity test asserts the old menu's
## quit CONNECTION rather than pressing it. Same one-liner `meta_root.gd` used.
##
## `has_signal` guarded because the panel container is filled in by #573: the
## signal exists once that lands, and connecting a signal that is not there yet
## would be an error rather than a no-op.
func _connect_panels() -> void:
	var panels := _panels()
	if panels == null:
		return
	if not panels.panel_dismissed.is_connected(_on_panel_dismissed):
		panels.panel_dismissed.connect(_on_panel_dismissed)
	if panels.has_signal(&"quit_requested") \
			and not panels.is_connected(&"quit_requested", _on_quit_requested):
		panels.connect(&"quit_requested", _on_quit_requested)


func _on_panel_dismissed(_id: StringName) -> void:
	var panels := _panels()
	if panels != null:
		panels.hide_all()
	back()


func _on_quit_requested() -> void:
	get_tree().quit()


## A leaf's panel is raised when the camera ARRIVES, not when it sets off — the
## lobby should not be on screen while the graph is still travelling toward it.
## Latched, because `set_progress(1.0)` is reached on every frame after the last.
func _route_focus_panel() -> void:
	var item := tree.get_item(focus_id)
	if item == null or not item.is_leaf() or item.panel == &"":
		return
	if _routed_panel == item.panel:
		return
	var panels := _panels()
	if panels == null:
		return
	_routed_panel = item.panel
	panels.show_panel(item.panel)


## Allocation is "on the focus path" (#569) — an identity change, not motion, so
## it lands at once rather than being tweened.
func _sync_allocation() -> void:
	var path := tree.path_to(focus_id)
	for id in _views:
		(_views[id] as MenuNodeView).allocated = path.has(id)
	for key in _edges:
		var edge: MenuEdgeView = _edges[key]
		var parent_view: MenuNodeView = _views[tree.parent_of(key)]
		var child_view: MenuNodeView = _views[key]
		edge.lit = parent_view.allocated and child_view.allocated


## Snapshots where every view is now, and where the new focus wants it, so
## [method set_progress] is a straight interpolation between two poses.
func _capture_transition() -> void:
	_from_pose = {}
	_to_pose = {}
	var homes := FrontmatterLayout.solve(tree)
	var path := tree.path_to(focus_id)
	for id in _views:
		var view: MenuNodeView = _views[id]
		_from_pose[id] = [view.position, view.scale.x]
		_to_pose[id] = _target_pose(id, homes, path)


## A view is at its canonical home when its PARENT is on the focus path — which
## is the whole of "grow, don't cut": the focus's children fan out, everything
## deeper stays collapsed on its own parent, and the root is always home because
## it has no parent to be anywhere else.
func _target_pose(id: StringName, homes: Dictionary, path: Array[StringName]) -> Array:
	var parent := tree.parent_of(id)
	if parent == &"" or path.has(parent):
		return [homes[id] as Vector2, 1.0]
	var slots := FrontmatterLayout.preview_slots(tree, parent)
	return [slots.get(id, homes[id]) as Vector2, FrontmatterLayout.PREVIEW_SCALE]


func _build_views() -> void:
	var homes := FrontmatterLayout.solve(tree)
	for id in tree.ids():
		var view: MenuNodeView = _NODE_VIEW.instantiate()
		view.name = String(id)
		_graph_layer.add_child(view)
		view.bind(tree.get_item(id))
		view.position = homes[id]
		_views[id] = view


## One edge per parent/child pair, keyed by the CHILD's id — a tree, so a child
## has exactly one incoming edge, which is also the "hero keeps its incoming
## edge" affordance #572 hangs its back button on.
func _build_edges() -> void:
	for id in tree.ids():
		for child_id in tree.children_of(id):
			var edge: MenuEdgeView = _EDGE_VIEW.instantiate()
			edge.name = "edge_%s" % child_id
			_graph_layer.add_child(edge)
			edge.connect_views(_views[id], _views[child_id])
			_edges[child_id] = edge


## Both endpoints of every edge, every frame of a transition. Cheap at nine
## edges, and it is what makes "edges never pop" true by construction rather
## than by nothing having moved yet.
func _push_edges() -> void:
	for child_id in _edges:
		var edge: MenuEdgeView = _edges[child_id]
		var parent_view: MenuNodeView = _views[tree.parent_of(child_id)]
		edge.set_endpoints(parent_view.position, (_views[child_id] as MenuNodeView).position)


func _clear() -> void:
	for child in _graph_layer.get_children():
		_graph_layer.remove_child(child)
		child.queue_free()
	_views = {}
	_edges = {}
	_from_pose = {}
	_to_pose = {}


## The player's accessibility setting, read straight off [GameSettings].
##
## [b]A direct, statically-typed read, deliberately.[/b] `GameSettings`'s own
## docstring argues that retiring a setting must break every call site at
## COMPILE time rather than silently read as null — so renaming `reduce_motion`
## has to fail `mise run check` here, which a reflective `get_property_list()`
## lookup would have quietly swallowed by falling back to the export.
##
## The one guard is the EDITOR, and it is a different question: project
## autoloads are not in the editor's tree, and this script is `@tool` so #578's
## live tab can mount it. That is about the autoload existing, not the property.
func _resolve_reduce_motion() -> bool:
	if Engine.is_editor_hint():
		return reduce_motion
	return Settings.current.reduce_motion
