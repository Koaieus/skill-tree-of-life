## Bottom-panel preview harness. Holds the world (origin + five fanned targets
## inside a SubViewport) and a tiny control strip: Fire button, status, and a
## read-only summary of the loaded coordinator's exports.
##
## The coordinator itself lives wherever the user is editing it — this panel
## just keeps a live reference and [code]duplicate()[/code]'s it on every Fire
## so each shot uses the inspector's *current* state.
##
## The summary is regenerated on Fire (not on inspector edit) — there's no
## clean signal for "inspector property changed" in Godot 4. Re-fire to see
## the snapshot.
@tool
extends PanelContainer

const _DEFAULT_DAMAGE: float = 5.0
# Outer ring sits this many pixels inside the viewport edge — leaves room for
# the SkillNode visual + a hit-flash without clipping.
const _RING_MARGIN: float = 48.0
# Inner ring radius as a fraction of the outer ring's. ~0.5 keeps near targets
# clearly distinct from far ones at any viewport size.
const _INNER_RING_FRAC: float = 0.5
const _DIR_COUNT: int = 8

@onready var fire_button: Button = %FireButton
@onready var status_label: Label = %StatusLabel
@onready var values_label: RichTextLabel = %ValuesLabel
@onready var origin: SkillNode = %Origin
@onready var targets_root: Node2D = %Targets
@onready var vfx_layer: Node2D = %VFXLayer
@onready var world: SubViewport = %World
@onready var background: ColorRect = %Background

var _coordinator: VFXCoordinator


func _ready() -> void:
	fire_button.pressed.connect(_fire)
	world.size_changed.connect(_layout_world)
	_layout_world()
	_refresh_status()


## Called by the EditorPlugin when the inspector button fires.
func load_coordinator(coord: VFXCoordinator) -> void:
	_coordinator = coord
	_refresh_status()


func _refresh_status() -> void:
	if not is_instance_valid(_coordinator):
		_coordinator = null
		status_label.text = "No coordinator loaded — select a VFXCoordinator in the inspector and hit \"Open in VFX Playground\"."
		values_label.text = ""
		fire_button.disabled = true
		return
	status_label.text = "%s (%s)" % [_coordinator.name, _coordinator.get_class()]
	fire_button.disabled = false
	values_label.text = _build_values_text(_coordinator)


# Use the instance's property list filtered by SCRIPT_VARIABLE, not
# `Script.get_script_property_list()` — the latter doesn't reliably include
# `@export` entries in Godot 4. Walking the instance also covers the full
# inheritance chain for free.
func _build_values_text(coord: VFXCoordinator) -> String:
	var lines: PackedStringArray = []
	for p in coord.get_property_list():
		var usage: int = p.usage
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
			continue
		var prop_name: String = p.name
		lines.append("[b]%s[/b] = %s" % [prop_name, _format_value(coord.get(prop_name))])
	if lines.is_empty():
		return "[i]<no exports>[/i]"
	return "\n".join(lines)


func _format_value(v: Variant) -> String:
	if v == null:
		return "[i]<null>[/i]"
	if v is bool:
		return "true" if v else "false"
	if v is float:
		# NOT `%.3g` — GDScript's `%` has no `g` conversion, so that form pushed
		# an "unsupported format character" error on every float formatted here.
		return String.num(v, 3)
	if v is Vector2:
		return "(%.2f, %.2f)" % [v.x, v.y]
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


func _gather_targets() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for c in targets_root.get_children():
		if c is SkillNode:
			out.append(c)
	return out


# Re-positions origin (centre) and targets (two elliptical rings of eight
# cardinal/ordinal directions) to the current SubViewport size. Hooked to
# `world.size_changed`, so as the SubViewportContainer stretches with the
# panel the gameplay area follows.
#
# Target order in the scene tree is significant: indices 0..7 are the near
# ring (N, NE, E, SE, S, SW, W, NW), 8..15 are the far ring in the same
# direction order. `_DIR_COUNT` keys the modulo.
func _layout_world() -> void:
	if world == null or background == null or origin == null or targets_root == null:
		return
	var size := Vector2(world.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	background.size = size
	var center := size * 0.5
	origin.position = center
	var targets := _gather_targets()
	var n := targets.size()
	if n <= 0:
		return
	# Elliptical rings — fill rectangular panels without distorting the
	# direction angles (cos/sin still correspond to N/E etc).
	var rx_outer := maxf(20.0, size.x * 0.5 - _RING_MARGIN)
	var ry_outer := maxf(20.0, size.y * 0.5 - _RING_MARGIN)
	for i in n:
		var dir_idx := i % _DIR_COUNT
		var ring_idx := i / _DIR_COUNT
		var ring_scale := 1.0 if ring_idx >= 1 else _INNER_RING_FRAC
		# dir_idx 0 = North (up). Screen Y points down, so North is angle -π/2.
		var dir_angle := -PI * 0.5 + float(dir_idx) * TAU / float(_DIR_COUNT)
		var offset := Vector2(cos(dir_angle) * rx_outer, sin(dir_angle) * ry_outer) * ring_scale
		targets[i].position = center + offset


func _fire() -> void:
	if not is_instance_valid(_coordinator):
		_coordinator = null
		_refresh_status()
		return
	var targets := _gather_targets()
	if origin == null or targets.is_empty():
		return
	for t in targets:
		t.refill()
	var outcome := AttackOutcome.new()
	for t in targets:
		var hit := DamageInstance.new()
		hit.amount = _DEFAULT_DAMAGE
		hit.origin = origin
		hit.target = t
		outcome.hits.append(hit)
		# Also populate the timeline so MagicBounceCoordinator (which reads it,
		# not `hits`) renders. No propagation here — one JUMP event per target
		# on beat 0. ArrowVolleyCoordinator ignores the timeline and reads hits.
		var ev := PropagationEvent.new()
		ev.beat = 0
		ev.verb = PropagationEvent.Verb.JUMP
		ev.origin = origin
		ev.target = t
		ev.damage = hit
		outcome.timeline.append(ev)
	# `duplicate()` with default flags (15) copies signals + groups + scripts +
	# uses instantiation. `duplicate(true)` would coerce the bool to int 1 =
	# DUPLICATE_SIGNALS only, dropping the script — the cast then returns null
	# and Fire silently no-ops.
	var runtime := _coordinator.duplicate() as VFXCoordinator
	if runtime == null:
		push_warning("VFX Playground: duplicate did not return a VFXCoordinator")
		return
	vfx_layer.add_child(runtime)
	_refresh_status()
	await runtime.play(outcome)
	runtime.queue_free()
