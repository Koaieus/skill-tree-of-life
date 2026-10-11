class_name LanternLayer
extends Node

## The dynamic half of the vision field: every [Lantern] of the local viewer's
## camp, uploaded each frame as its own small disc set beside FogOverlay's
## circle tiles, and the nodes under those discs given their revealed look.
##
## [b]View-only.[/b] It never touches [VisionSystem]'s circles, its
## `visibility_changed` / `vision_render_tick`, [method FogOverlay.set_sources]
## or any logical flag; it writes two shader globals and
## [member SkillNode.lantern_lit], nothing else. The tile index is not rebuilt
## for lanterns — `vision_field_darkness` unions both sets in the shader.
## See docs/domain/vision-system.md, "Lanterns".
##
## Sleeps ([code]set_process(false)[/code]) while no lantern exists and no
## fade is running; a [Lantern] entering the tree wakes it via [method wake].

const GROUP := &"vision_lantern_layers"

## Its parent, wired in `fog_overlay.tscn`. The vision system is read off it
## each frame, so the layer follows FogOverlay's own injection without a
## second wire in every composing scene.
@export var fog_overlay: FogOverlay
## Overrides [member fog_overlay]'s vision system when set. Null on both is
## legal (`scenes/overlay_perf_harness.gd`): lanterns upload unfiltered and no
## node is ever lit.
@export var vision_system: VisionSystem
## Upload cap, and so the bound on the per-pixel lantern loop in every
## vision-field consumer. Overflow drops the excess with a warn-once.
## Tentative, easy to change.
@export_range(1, 256) var max_lanterns: int = 64:
	set(value):
		max_lanterns = value
		_alloc_texture()
## How long a freed carrier's last disc takes to shrink to 0, so the fog
## closes behind it instead of snapping shut. Tentative, easy to change.
@export_range(0.0, 5.0, 0.01, "suffix:s") var fade_seconds: float = 0.25
## Cell size of the static node grid the lit pass queries. Tentative.
@export_range(16.0, 1024.0, 1.0, "suffix:px") var node_grid_cell: float = 128.0:
	set(value):
		node_grid_cell = value
		_grid_dirty = true

## Discs uploaded on the last frame (`vision_lantern_count`). Read-only seam.
var uploaded_count: int = 0
## The `vision_lanterns_tex` texture: texel i = (x, y, radius, 0). Read-only.
var texture: ImageTexture = null
## The CPU side of [member texture], as last uploaded. Read-only seam: a
## headless (dummy-renderer) texture does not read back its updates.
var image: Image = null
var _warned_overflow := false
# instance_id -> {pos, radius} of every disc that passed the filter last frame,
# so a lantern gone this frame becomes a ghost from where it was.
var _last_discs: Dictionary = {}
# Fading discs: {pos, radius, t} with t seconds elapsed.
var _ghosts: Array[Dictionary] = []
# The nodes lit last frame, by instance id (a freed node == null).
var _lit: Dictionary = {}
# Vector2i cell -> Array[SkillNode]. Static: rebuilt only when the node set changes.
var _grid: Dictionary = {}
var _grid_dirty := true
var _grid_graph: Graph = null


func _ready() -> void:
	add_to_group(GROUP)
	_alloc_texture()
	_upload(0)
	set_process(not get_tree().get_nodes_in_group(Lantern.GROUP).is_empty())


func _exit_tree() -> void:
	_clear_lit({})


## Called by a [Lantern] entering the tree.
func wake() -> void:
	set_process(true)


func _vision() -> VisionSystem:
	if vision_system != null:
		return vision_system
	return fog_overlay.vision_system if fog_overlay != null else null


func _process(delta: float) -> void:
	var vs := _vision()
	var discs: Array[Dictionary] = []
	var seen: Dictionary = {}
	for n in get_tree().get_nodes_in_group(Lantern.GROUP):
		var l := n as Lantern
		if l == null:
			continue
		# A carrier can outlive its source (an arrow in flight after its
		# shooter dies): a freed source is no camp's.
		var src: Entity = l.source if is_instance_valid(l.source) else null
		if vs != null and not vs.is_viewer_camp(src):
			continue
		var d := {"pos": l.global_position, "radius": l.radius}
		seen[l.get_instance_id()] = d
		discs.append(d)
	for id in _last_discs:
		if not seen.has(id) and fade_seconds > 0.0:
			var g: Dictionary = _last_discs[id]
			_ghosts.append({"pos": g.pos, "radius": g.radius, "r0": g.radius, "t": 0.0})
	_last_discs = seen
	var live: Array[Dictionary] = []
	for g in _ghosts:
		g.t += delta
		if g.t < fade_seconds:
			g.radius = g.r0 * (1.0 - g.t / fade_seconds)
			live.append(g)
	_ghosts = live
	discs.append_array(_ghosts)

	if discs.size() > max_lanterns:
		if not _warned_overflow:
			_warned_overflow = true
			push_warning("LanternLayer: %d lanterns exceed the %d cap; %d are not rendered."
				% [discs.size(), max_lanterns, discs.size() - max_lanterns])
		discs = discs.slice(0, max_lanterns)
	else:
		_warned_overflow = false
	for i in discs.size():
		var d: Dictionary = discs[i]
		image.set_pixel(i, 0, Color(d.pos.x, d.pos.y, d.radius, 0.0))
	_upload(discs.size())
	_light(vs, discs)
	if discs.is_empty():
		set_process(false)


func _upload(count: int) -> void:
	uploaded_count = count
	if count > 0:
		texture.update(image)
	RenderingServer.global_shader_parameter_set(&"vision_lantern_count", count)


func _alloc_texture() -> void:
	image = Image.create(max_lanterns, 1, false, Image.FORMAT_RGBAF)
	texture = ImageTexture.create_from_image(image)
	RenderingServer.global_shader_parameter_set(&"vision_lanterns_tex", texture)


## Lit pass: lanterns x the nodes in the cells each disc covers, never a walk
## over the whole graph. Nodes already [member SkillNode.revealed] are skipped.
func _light(vs: VisionSystem, discs: Array[Dictionary]) -> void:
	var now: Dictionary = {}
	var graph: Graph = vs.graph if vs != null else null
	if graph != null:
		_ensure_grid(graph)
		for d in discs:
			var pos: Vector2 = d.pos
			var r: float = d.radius
			var lo := Vector2i(floor((pos.x - r) / node_grid_cell), floor((pos.y - r) / node_grid_cell))
			var hi := Vector2i(floor((pos.x + r) / node_grid_cell), floor((pos.y + r) / node_grid_cell))
			for cx in range(lo.x, hi.x + 1):
				for cy in range(lo.y, hi.y + 1):
					var cell: Array = _grid.get(Vector2i(cx, cy), [])
					for sn: SkillNode in cell:
						if not is_instance_valid(sn) or sn.revealed:
							continue
						if sn.global_position.distance_squared_to(pos) <= r * r:
							now[sn.get_instance_id()] = sn
	for id in now:
		(now[id] as SkillNode).lantern_lit = true
	_clear_lit(now)


func _clear_lit(now: Dictionary) -> void:
	for id in _lit:
		if not now.has(id):
			var sn = instance_from_id(id)
			if sn != null and is_instance_valid(sn):
				(sn as SkillNode).lantern_lit = false
	_lit = now


func _ensure_grid(graph: Graph) -> void:
	if graph != _grid_graph:
		if _grid_graph != null and is_instance_valid(_grid_graph):
			_grid_graph.node_added.disconnect(_mark_grid_dirty)
			_grid_graph.node_removed.disconnect(_mark_grid_dirty)
		_grid_graph = graph
		graph.node_added.connect(_mark_grid_dirty)
		graph.node_removed.connect(_mark_grid_dirty)
		_grid_dirty = true
	if not _grid_dirty:
		return
	_grid_dirty = false
	_grid.clear()
	for sn in graph.get_skill_nodes():
		var c := Vector2i(floor(sn.global_position.x / node_grid_cell), floor(sn.global_position.y / node_grid_cell))
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(sn)


func _mark_grid_dirty(_sn: SkillNode = null) -> void:
	_grid_dirty = true
