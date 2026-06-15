## Bottom-panel preview harness for spells. Holds a small isolated graph
## (caster + 4×4 grid of defender-owned nodes wired with cardinal edges),
## a control strip (Cast + status + read-only spell summary), and the VFX
## layer the resolved outcome plays on.
##
## The spell itself lives wherever the user is editing it — this panel
## keeps a live reference and re-reads its exports on every Cast, so the
## inspector is the single source of truth. Damage application is deferred
## to the VFX coordinator (DamageInstance on arrival), matching gameplay.
@tool
extends PanelContainer

const _GRID_COLS: int = 4
const _GRID_ROWS: int = 4
const _CASTER_ZONE_W: float = 130.0
const _GRID_MARGIN: float = 40.0
const _SELECTED_TINT: Color = Color(1.0, 0.7, 0.7, 1.0)
const _UNSELECTED_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

@onready var cast_button: Button = %CastButton
@onready var status_label: Label = %StatusLabel
@onready var values_label: RichTextLabel = %ValuesLabel
@onready var world: SubViewport = %World
@onready var background: ColorRect = %Background
@onready var vfx_layer: Node2D = %VFXLayer
@onready var graph: Graph = %Graph
@onready var caster_entity: Entity = %CasterEntity
@onready var defender_entity: Entity = %DefenderEntity
@onready var caster_node: SkillNode = %CasterNode

var _spell: SpellDef = null
var _selected_target: SkillNode = null


func _ready() -> void:
	cast_button.pressed.connect(_cast)
	world.size_changed.connect(_layout_world)
	# Belt and suspenders: SkillNode's Area2D wires `input_event → left_clicked`
	# via signal, but Godot only routes the pick through a SubViewport when
	# the viewport opts in to physics picking. Set it here too in case the
	# panel scene was authored / cached without it.
	world.physics_object_picking = true
	world.handle_input_locally = true
	_build_grid_edges()
	for sn in graph.get_skill_nodes():
		sn.left_clicked.connect(_on_target_clicked)
	# Default seed = the cell at row 2, col 1 — interior enough that a
	# 3-hop spell reaches most of the grid; corner casts also work but
	# undersell the BFS fan-out.
	var nodes := graph.get_skill_nodes()
	if nodes.size() > 9:
		_selected_target = nodes[9]
	_layout_world()
	_refresh_status()


## Called by the EditorPlugin when the inspector button fires.
func load_spell(spell: SpellDef) -> void:
	_spell = spell
	_refresh_status()


# A 4×4 cardinal grid alone gives 3 distinct degrees (2 / 3 / 4), and the
# four interior nodes are all degree 4 — too uniform to read how a spell
# behaves at hubs vs leaves. The handful of diagonal + extra edges below
# break that into a 1..6 range without changing node positions: a
# stand-out hub (T5 → 6), a near-hub (T10 → 5), a true leaf (T15 → 1),
# and a couple of corners / edges that are now distinct from each other.
const _EXTRA_EDGES: Array[Vector2i] = [
	Vector2i(0, 5),   # corner→interior diagonal — T0 → 3, T5 +1
	Vector2i(2, 7),   # corner→edge diagonal — T2 → 4, T7 → 4
	Vector2i(8, 13),  # edge→interior diagonal — T8 → 4, T13 +1
	Vector2i(5, 11),  # interior→edge shortcut — promotes T5 into a hub
	Vector2i(3, 6),   # cross-link near NE corner — T3 → 3, T6 → 5
]
# Cardinal edges to skip from the regular grid — used to carve a leaf
# (T15 isolated to a single connection) and a low-degree pocket.
const _SKIP_CARDINAL_EDGES: Array[Vector2i] = [
	Vector2i(11, 15),  # T15 loses its second neighbour, becomes a degree-1 leaf
	Vector2i(12, 13),  # T12 left more isolated (degree 1 too), T13 less crowded
]


# Connect cardinal neighbours in the grid via Edge nodes added to
# graph.edges_container. Grid ordering matches the .tscn — row-major,
# 4 columns wide.
func _build_grid_edges() -> void:
	var nodes := graph.get_skill_nodes()
	if nodes.size() < _GRID_COLS * _GRID_ROWS:
		return
	var existing := graph.get_edges()
	if not existing.is_empty():
		return  # already built (e.g. panel re-entered)
	for r in _GRID_ROWS:
		for c in _GRID_COLS:
			var i := r * _GRID_COLS + c
			if c < _GRID_COLS - 1 and not _is_skipped(i, i + 1):
				_add_edge(nodes[i], nodes[i + 1])
			if r < _GRID_ROWS - 1 and not _is_skipped(i, i + _GRID_COLS):
				_add_edge(nodes[i], nodes[i + _GRID_COLS])
	for pair in _EXTRA_EDGES:
		_add_edge(nodes[pair.x], nodes[pair.y])


func _is_skipped(a: int, b: int) -> bool:
	for pair in _SKIP_CARDINAL_EDGES:
		if (pair.x == a and pair.y == b) or (pair.x == b and pair.y == a):
			return true
	return false


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := Edge.new()
	e.from = a
	e.to = b
	graph.edges_container.add_child(e)


func _on_target_clicked(node: SkillNode) -> void:
	if node == null or node.owned_by == caster_entity:
		return
	_selected_target = node
	_refresh_status()


func _refresh_status() -> void:
	for sn in graph.get_skill_nodes():
		sn.modulate = _SELECTED_TINT if sn == _selected_target else _UNSELECTED_TINT
	if not is_instance_valid(_spell):
		_spell = null
		status_label.text = "No spell loaded — select a SpellDef in the inspector and hit \"Open in Spell Playground\"."
		values_label.text = ""
		cast_button.disabled = true
		return
	var target_name: String = _selected_target.name if _selected_target != null else "—"
	status_label.text = "%s · seed → %s" % [_spell.name, target_name]
	cast_button.disabled = (_selected_target == null)
	values_label.text = _build_values_text(_spell)


func _build_values_text(spell: SpellDef) -> String:
	var lines: PackedStringArray = []
	for p in spell.get_property_list():
		var usage: int = p.usage
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
			continue
		var prop_name: String = p.name
		lines.append("[b]%s[/b] = %s" % [prop_name, _format_value(spell.get(prop_name))])
	if lines.is_empty():
		return "[i]<no exports>[/i]"
	return "\n".join(lines)


func _format_value(v: Variant) -> String:
	if v == null:
		return "[i]<null>[/i]"
	if v is bool:
		return "true" if v else "false"
	if v is float:
		return "%.3s" % v
	if v is int:
		return str(v)
	if v is String:
		var s: String = v
		return "\"%s\"" % (s if s.length() < 40 else s.substr(0, 37) + "…")
	if v is Array:
		return "[%d item(s)]" % (v as Array).size()
	if v is PackedScene:
		var ps: PackedScene = v
		return ps.resource_path if ps.resource_path != "" else "<inline PackedScene>"
	if v is Resource:
		var r: Resource = v
		var path: String = r.resource_path
		if path != "":
			return "%s (%s)" % [path.get_file(), r.get_class()]
		return "<inline %s>" % str(r.get_class())
	return str(v)


# Lay out caster (left strip) and 4×4 grid (right area) in the current
# viewport. Cell pitch = min of available width/height for the grid, so
# the layout reads correctly at any panel aspect ratio.
func _layout_world() -> void:
	if world == null or background == null:
		return
	var size := Vector2(world.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	background.size = size
	caster_node.position = Vector2(_CASTER_ZONE_W * 0.5, size.y * 0.5)
	var grid_w := maxf(20.0, size.x - _CASTER_ZONE_W - _GRID_MARGIN)
	var grid_h := maxf(20.0, size.y - 2.0 * _GRID_MARGIN)
	var pitch := minf(grid_w / float(_GRID_COLS - 1), grid_h / float(_GRID_ROWS - 1))
	var grid_center := Vector2(_CASTER_ZONE_W + grid_w * 0.5, size.y * 0.5)
	var nodes := graph.get_skill_nodes()
	for i in nodes.size():
		var r := i / _GRID_COLS
		var c := i % _GRID_COLS
		var dx := (float(c) - (_GRID_COLS - 1) * 0.5) * pitch
		var dy := (float(r) - (_GRID_ROWS - 1) * 0.5) * pitch
		nodes[i].position = grid_center + Vector2(dx, dy)
	for e in graph.get_edges():
		e.queue_redraw()


func _cast() -> void:
	if not is_instance_valid(_spell) or _selected_target == null:
		return
	if _spell.vfx_coordinator_scene == null:
		# No headless fallback — that path would apply damage synchronously
		# at cast time, which is the exact bug we want to make impossible.
		# Wire a coord scene on the SpellDef.
		push_warning("Spell Playground: spell has no vfx_coordinator_scene — Cast skipped")
		return
	for sn in graph.get_skill_nodes():
		sn.refill()
	var outcome := SpellResolver.resolve(
			_spell, _selected_target, caster_node, caster_entity, graph)
	if outcome.hits.is_empty():
		return
	var coord := _spell.vfx_coordinator_scene.instantiate() as VFXCoordinator
	if coord == null:
		push_warning("Spell Playground: vfx_coordinator_scene root is not a VFXCoordinator")
		return
	# Production VFX defaults assume a full-screen battlefield (apex 420 px).
	# In the playground's ~340 px viewport that arc sends the projectile off
	# the top for most of the flight — read by the user as "no projectile,
	# damage just appeared". Override with an arc that fits the panel.
	if coord is RangedVolleyCoordinator:
		var rvc := coord as RangedVolleyCoordinator
		var arc := BezierArcPath.new()
		arc.apex_height = 70.0
		rvc.projectile_path = arc
	vfx_layer.add_child(coord)
	await coord.play(outcome)
	coord.queue_free()
