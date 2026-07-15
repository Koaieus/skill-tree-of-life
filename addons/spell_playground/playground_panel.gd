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
## Emitted when the panel wants the host to discard and re-instantiate it
## (#144) — e.g. a stuck `_casting` lock or leftover VFXLayer children from
## an interrupted cast that Reset (health refill only) can't clear.
signal reload_requested

const _EDGE_SCENE := preload("res://graph/edge.tscn")

const _GRID_COLS: int = 4
const _GRID_ROWS: int = 4
const _CASTER_ZONE_W: float = 130.0
const _GRID_MARGIN: float = 40.0
const _SELECTED_TINT: Color = Color(1.0, 0.7, 0.7, 1.0)
const _UNSELECTED_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

@onready var cast_button: Button = %CastButton
@onready var reset_button: Button = %ResetButton
@onready var reload_button: Button = %ReloadButton
@onready var status_label: Label = %StatusLabel
@onready var values_label: RichTextLabel = %ValuesLabel
@onready var world: SubViewport = %World
@onready var background: ColorRect = %Background
@onready var vfx_layer: Node2D = %VFXLayer
@onready var graph: Graph = %Graph
@onready var caster_entity: Entity = %CasterEntity
@onready var defender_entity: Entity = %DefenderEntity
@onready var caster_node: SkillNode = %CasterNode
@onready var spell_list: OptionButton = %SpellList
@onready var browse_button: Button = %BrowseButton
@onready var _world_container: SubViewportContainer = $HBox/WorldContainer

var _spell: SpellDef = null
var _selected_target: SkillNode = null
## True from Cast until the coordinator finishes playing. Damage lands on VFX
## arrival, so a refill (or a second cast) during that window would be undone
## by a hit still in the air. Both buttons are gated on it rather than trying
## to cancel in-flight damage.
var _casting: bool = false
## Populated from the caster's own spellbook (the same 6 spells the .tscn
## already preloads for CasterEntity) — no separate directory scan needed.
var _listed_spells: Array[SpellDef] = []


func _ready() -> void:
	cast_button.pressed.connect(_cast)
	reset_button.pressed.connect(_reset_state)
	reload_button.pressed.connect(reload_requested.emit)
	world.size_changed.connect(_layout_world)
	_populate_spell_list()
	spell_list.item_selected.connect(_on_spell_list_selected)
	browse_button.pressed.connect(_on_browse_pressed)
	# Belt and suspenders: SkillNode's Area2D wires `input_event → left_clicked`
	# via signal, but Godot only routes the pick through a SubViewport when
	# the viewport opts in to physics picking. Set it here too in case the
	# panel scene was authored / cached without it.
	world.physics_object_picking = true
	world.handle_input_locally = true
	# Layout must run before edges are wired: Edge captures its Line2D
	# endpoints at connect-time and only redraws on owner/radius/archetype
	# changes, not position — building edges first would freeze them at the
	# nodes' pre-layout (overlapping) .tscn positions.
	_layout_world()
	_build_grid_edges()
	# Hit-test clicks directly on the SubViewportContainer rather than relying
	# on Area2D pickup through the SubViewport. In editor bottom-panel context
	# `physics_object_picking` routing has been unreliable — events reach the
	# container, but not always the Area2D inside the SubViewport. The
	# container is 1:1 with the SubViewport (stretch=true, no camera), so
	# `event.position` IS world position; we walk skill nodes and pick the
	# closest one within its `radius`. Bypasses the targeting-rule split that
	# production gameplay applies — the playground deliberately lets any node
	# (incl. the caster) be selected as seed.
	_world_container.gui_input.connect(_on_world_gui_input)
	# Default seed = the cell at row 2, col 1 — interior enough that a
	# 3-hop spell reaches most of the grid; corner casts also work but
	# undersell the BFS fan-out.
	var nodes := graph.get_skill_nodes()
	if nodes.size() > 9:
		_selected_target = nodes[9]
	_refresh_status()


## Called by the EditorPlugin whenever a SpellDef becomes the inspected
## object. Tolerates null (e.g. selecting something that isn't a SpellDef
## via something other than the inspector) and rapid re-fires.
func load_spell(spell: SpellDef) -> void:
	if spell == _spell:
		_refresh_status()
		return
	_spell = spell
	_sync_spell_list_selection()
	_refresh_status()


## Fills the dropdown from the caster's spellbook so any of the 6 shipped
## spells can be previewed without leaving the Sandbox screen or round-
## tripping through the Inspector.
func _populate_spell_list() -> void:
	_listed_spells.clear()
	spell_list.clear()
	spell_list.add_item("Pick a spell…")
	spell_list.set_item_disabled(0, true)
	if caster_entity == null or caster_entity.spellbook == null:
		return
	for spell in caster_entity.spellbook.spells:
		if spell == null:
			continue
		_listed_spells.append(spell)
		spell_list.add_item(spell.name if spell.name != "" else spell.resource_path.get_file())
	# OptionButton auto-selects the first enabled item if left untouched,
	# which would show e.g. "Spark" while the panel still has no spell
	# loaded. Pin it to the disabled placeholder until something is picked.
	spell_list.select(0)


func _on_spell_list_selected(index: int) -> void:
	var spell_index := index - 1  # slot 0 is the disabled placeholder
	if spell_index < 0 or spell_index >= _listed_spells.size():
		return
	load_spell(_listed_spells[spell_index])


## Keeps the dropdown showing whichever spell is actually loaded, including
## when it arrived via the Inspector "Open Spell Playground" sync rather than
## a dropdown pick.
func _sync_spell_list_selection() -> void:
	var idx := _listed_spells.find(_spell)
	spell_list.select(idx + 1 if idx >= 0 else 0)


## Reveals attack/spell/defs/ in the editor's FileSystem dock — a shortcut to
## authoring a new SpellDef .tres alongside the existing six.
func _on_browse_pressed() -> void:
	if not Engine.is_editor_hint():
		return
	var dock := EditorInterface.get_file_system_dock()
	if dock == null:
		return
	var target := "res://attack/spell/defs/"
	if not _listed_spells.is_empty() and _listed_spells[0].resource_path != "":
		target = _listed_spells[0].resource_path
	dock.navigate_to_path(target)


## Called by the EditorPlugin on `property_edited` — the spell reference
## hasn't changed but one of its exports has. Re-render the readout so
## live edits show up without re-clicking the inspector button.
func refresh_from_spell() -> void:
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
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	graph.edges_container.add_child(e)


func _on_target_clicked(node: SkillNode) -> void:
	# No targeting-rule gate here — the playground is for *previewing* what
	# a spell does from an arbitrary seed; the rule check belongs to gameplay
	# casting, not to authoring inspection.
	if node == null:
		return
	_selected_target = node
	_refresh_status()


func _on_world_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit := _pick_node_at(mb.position)
	if hit != null:
		_on_target_clicked(hit)
		# Container handles the click; don't let it leak back into the editor.
		_world_container.accept_event()


# Find the topmost skill node whose disc covers `world_pos`. SubViewport has
# no camera and stretch=true, so the container's local coords ARE world coords.
# Iterates grid + caster (caster legal-as-seed per playground policy).
func _pick_node_at(world_pos: Vector2) -> SkillNode:
	var best: SkillNode = null
	var best_d2: float = INF
	var candidates: Array[SkillNode] = graph.get_skill_nodes()
	if caster_node != null:
		candidates.append(caster_node)
	for sn in candidates:
		if sn == null:
			continue
		var d2 := world_pos.distance_squared_to(sn.position)
		var r := sn.radius
		if d2 <= r * r and d2 < best_d2:
			best = sn
			best_d2 = d2
	return best


func _refresh_status() -> void:
	for sn in graph.get_skill_nodes():
		sn.modulate = _SELECTED_TINT if sn == _selected_target else _UNSELECTED_TINT
	if not is_instance_valid(_spell):
		_spell = null
		status_label.text = "No spell loaded — select a SpellDef in the inspector to sync it here."
		values_label.text = ""
		cast_button.disabled = true
		return
	var target_name: String = _selected_target.name if _selected_target != null else "—"
	status_label.text = "%s · seed → %s" % [_spell.name, target_name]
	cast_button.disabled = (_selected_target == null) or _casting
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
		e.refresh_endpoints()


## The one and only place node health is restored. Casts deliberately do NOT
## auto-refill: damage accumulates across casts, so a node that no single spell
## can kill still dies to three of them — which is most of what this harness is
## for. Press Reset to get a pristine board back.
func _reset_state() -> void:
	_refill_all_nodes()
	_refresh_status()


func _refill_all_nodes() -> void:
	for sn in graph.get_skill_nodes():
		sn.refill()


## Gate Cast + Reset for the duration of a coordinator's play. Both would
## otherwise interleave with damage that only lands when the VFX arrives.
func _set_casting(value: bool) -> void:
	_casting = value
	reset_button.disabled = value
	_refresh_status()


func _cast() -> void:
	if _casting:
		return
	if not is_instance_valid(_spell) or _selected_target == null:
		return
	if _spell.vfx_coordinator_scene == null:
		# No headless fallback — that path would apply damage synchronously
		# at cast time, which is the exact bug we want to make impossible.
		# Wire a coord scene on the SpellDef.
		push_warning("Spell Playground: spell has no vfx_coordinator_scene — Cast skipped")
		return
	var outcome := SpellResolver.resolve(
			_spell, _selected_target, caster_node, caster_entity, graph)
	# Guard on the timeline, not `hits`: a zero-damage utility spell still has
	# a path to render (the coordinator reads the timeline).
	if outcome.timeline.is_empty():
		return
	var coord := _spell.vfx_coordinator_scene.instantiate() as VFXCoordinator
	if coord == null:
		push_warning("Spell Playground: vfx_coordinator_scene root is not a VFXCoordinator")
		return
	# Production VFX defaults assume a full-screen battlefield (apex 420 px).
	# In the playground's ~340 px viewport that arc sends the projectile off
	# the top for most of the flight — read by the user as "no projectile,
	# damage just appeared". Override with an arc that fits the panel.
	if coord is MagicBounceCoordinator:
		var mbc := coord as MagicBounceCoordinator
		var arc := BezierArcPath.new()
		arc.apex_height = 70.0
		mbc.projectile_path = arc
	vfx_layer.add_child(coord)
	_set_casting(true)
	await coord.play(outcome)
	coord.queue_free()
	# The panel can be torn down mid-play (plugin disabled, tab rebuilt); its
	# buttons are gone by then and re-enabling them would crash.
	if is_inside_tree():
		_set_casting(false)
