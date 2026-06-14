## Bottom-panel preview harness. Holds the world (origin + five fanned targets
## inside a SubViewport) and a tiny control strip: Fire button, status, and a
## read-only summary of the loaded coordinator's exports.
##
## The coordinator itself lives wherever the user is editing it — this panel
## just keeps a live reference and [code]duplicate(true)[/code]'s it on every
## Fire so each shot uses the inspector's *current* state.
##
## The summary is regenerated on Fire (not on inspector edit) — there's no
## clean signal for "inspector property changed" in Godot 4. Re-fire to see
## the snapshot.
@tool
extends PanelContainer

const _DEFAULT_DAMAGE: float = 5.0

@onready var fire_button: Button = %FireButton
@onready var status_label: Label = %StatusLabel
@onready var values_label: RichTextLabel = %ValuesLabel
@onready var origin: SkillNode = %Origin
@onready var targets_root: Node2D = %Targets
@onready var vfx_layer: Node2D = %VFXLayer

var _coordinator: VFXCoordinator


func _ready() -> void:
	fire_button.pressed.connect(_fire)
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


# Walk the coord's own script properties (one level — subclasses own their
# exports; if a future intermediate base ever defines exports, expand this
# to chain `get_base_script()`).
func _build_values_text(coord: VFXCoordinator) -> String:
	var script: Script = coord.get_script()
	if script == null:
		return "[i]<scriptless coordinator>[/i]"
	var lines: PackedStringArray = []
	for p: Dictionary in script.get_script_property_list():
		var name: String = p.name
		var usage: int = p.usage
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & PROPERTY_USAGE_CATEGORY) != 0:
			continue
		if (usage & PROPERTY_USAGE_GROUP) != 0:
			continue
		if (usage & PROPERTY_USAGE_SUBGROUP) != 0:
			continue
		lines.append("[b]%s[/b] = %s" % [name, _format_value(coord.get(name))])
	if lines.is_empty():
		return "[i]<no exports>[/i]"
	return "\n".join(lines)


func _format_value(v: Variant) -> String:
	if v == null:
		return "[i]<null>[/i]"
	if v is bool:
		return "true" if v else "false"
	if v is float:
		return "%.3g" % v
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
	# Duplicate so we don't reparent the edited instance — the original
	# keeps its place in whatever scene the user is editing. Exports come
	# along via duplicate(true).
	var runtime := _coordinator.duplicate(true) as VFXCoordinator
	if runtime == null:
		push_warning("VFX Playground: duplicate did not return a VFXCoordinator")
		return
	vfx_layer.add_child(runtime)
	_refresh_status()
	await runtime.play(outcome)
	runtime.queue_free()
