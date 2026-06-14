class_name VFXPlayground
extends Node2D

## Standalone harness for forging attack / spell VFX. No AP, no turns, no
## battle plan — fire the configured volley as often as you like and tweak
## path, timing, visuals live. Targets auto-refill before every fire so the
## ergonomics don't drift as you experiment.
##
## Scoped to [RangedVolleyCoordinator] today. Future melee / magic
## coordinators each get a sibling mode here; the harness shape
## (origin + targets + Fire + auto-refill) generalises, the controls panel
## is per-mode.
##
## Path editing: switch the "Path mode" to "Curve2D" and drag the points on
## the in-scene [Path2D] node — the next fire reads the updated curve
## directly. Once you're happy, save the [Curve2D] sub-resource to a `.tres`
## for use from a real attack def.

const _GLOWING_DOT_SCENE: PackedScene = preload(
		"res://ui/vfx/projectile/visual/glowing_dot.tscn")

enum PathMode { BEZIER_ARC, CURVE_2D }

@onready var origin: SkillNode = %Origin
@onready var targets_root: Node2D = %Targets
@onready var path_editor: Path2D = %PathEditor
@onready var vfx_layer: Node2D = %VFXLayer

@onready var fire_button: Button = %FireButton
@onready var path_mode_option: OptionButton = %PathModeOption
@onready var arc_height_spin: SpinBox = %ArcHeightSpin
@onready var flight_time_spin: SpinBox = %FlightTimeSpin
@onready var stagger_spin: SpinBox = %StaggerSpin
@onready var damage_spin: SpinBox = %DamageSpin
@onready var face_velocity_check: CheckBox = %FaceVelocityCheck
@onready var head_radius_spin: SpinBox = %HeadRadiusSpin
@onready var glow_radius_spin: SpinBox = %GlowRadiusSpin
@onready var trail_len_spin: SpinBox = %TrailLenSpin
@onready var head_color_picker: ColorPickerButton = %HeadColorPicker
@onready var glow_color_picker: ColorPickerButton = %GlowColorPicker
@onready var arc_height_row: Control = %ArcHeightRow


func _ready() -> void:
	_populate_path_modes()
	fire_button.pressed.connect(_fire)
	path_mode_option.item_selected.connect(_on_path_mode_changed)
	_on_path_mode_changed(path_mode_option.get_selected_id())


func _populate_path_modes() -> void:
	path_mode_option.clear()
	path_mode_option.add_item("Bezier arc (tunable apex)", PathMode.BEZIER_ARC)
	path_mode_option.add_item("Curve2D (drag the points)", PathMode.CURVE_2D)
	path_mode_option.selected = 0


func _on_path_mode_changed(id: int) -> void:
	# Arc-height knob is only meaningful in Bezier mode; hide it in Curve2D
	# to make the "edit the Path2D directly" UX self-evident.
	arc_height_row.visible = id == int(PathMode.BEZIER_ARC)
	path_editor.visible = id == int(PathMode.CURVE_2D)


func _gather_targets() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for c in targets_root.get_children():
		if c is SkillNode:
			out.append(c)
	return out


func _fire() -> void:
	var targets := _gather_targets()
	if origin == null or targets.is_empty():
		push_warning("VFXPlayground: need origin + at least one target")
		return
	# Auto-refill targets so the visual stays consistent across repeated
	# fires — the playground isn't about HP attrition.
	for t in targets:
		t.refill()
	var outcome := AttackOutcome.new()
	for t in targets:
		var hit := DamageInstance.new()
		hit.amount = damage_spin.value
		hit.origin = origin
		hit.target = t
		outcome.hits.append(hit)
	var coord := RangedVolleyCoordinator.new()
	coord.projectile_path = _build_path()
	coord.visual_scene = _build_visual_scene()
	coord.flight_time = flight_time_spin.value
	coord.stagger_per_shot = stagger_spin.value
	coord.face_velocity = face_velocity_check.button_pressed
	vfx_layer.add_child(coord)
	await coord.play(outcome)
	coord.queue_free()


func _build_path() -> ProjectilePath:
	match path_mode_option.get_selected_id():
		PathMode.BEZIER_ARC:
			var p := BezierArcPath.new()
			p.apex_height = arc_height_spin.value
			return p
		PathMode.CURVE_2D:
			var p := Curve2DPath.new()
			# Shared by reference — dragging Path2D points in-editor updates
			# the curve live; next fire picks up the new shape.
			p.curve = path_editor.curve
			return p
	return BezierArcPath.new()


# PackedScene exports are immutable from script, so build a runtime-tuned scene
# by mutating a fresh GlowingDot and `pack`ing it. Each fire packs anew —
# negligible cost, gives every projectile the current style without resaving
# the source .tscn.
func _build_visual_scene() -> PackedScene:
	var template := GlowingDot.new()
	template.head_radius = head_radius_spin.value
	template.head_glow_radius = glow_radius_spin.value
	template.trail_len = int(trail_len_spin.value)
	template.head_color = head_color_picker.color
	template.head_glow_color = glow_color_picker.color
	var live := PackedScene.new()
	live.pack(template)
	template.free()
	return live
