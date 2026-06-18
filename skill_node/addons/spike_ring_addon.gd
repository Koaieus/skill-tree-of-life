@tool
class_name SpikeRingAddon
extends SkillNodeAddon

## Offensive vertex-spike contribution: when the carrier is part of a phantom
## blade, the swept node drives spikes through whatever it sweeps — the
## design doc's "swung = offensive" half of sharpness. Adds `damage` to the
## per-particle `state.vertex_spikes` slot; SkillBlade reads it on node hits.
##
## Defensive side (blade-vs-blade collision, spike-attacks-incoming-blade
## structure) is explicitly out-of-scope per docs/design/skill_node_addons.md
## — collision model is open and "do not implement until specified".

@export var damage: float = 1.0
@export_range(4, 24, 1) var spike_count: int = 12
@export var spike_color: Color = Color(0.95, 0.55, 0.4, 0.95)
## How far out the spike tips reach beyond the carrier's radius.
@export_range(0.0, 1.0, 0.05) var spike_overshoot: float = 0.45
## Spike base width as a fraction of the carrier's radius.
@export_range(0.05, 0.6, 0.05) var spike_base: float = 0.18

var _radius: float = 32.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


func apply_to_blade(state: BladeState, particle_idx: int) -> void:
	state.vertex_spikes[particle_idx] += damage


func _draw() -> void:
	if _radius <= 0.0 or spike_count <= 0:
		return
	var base_half := _radius * spike_base * 0.5
	var tip_dist := _radius * (1.0 + spike_overshoot)
	var step := TAU / float(spike_count)
	for i in spike_count:
		var theta := i * step
		var radial := Vector2.from_angle(theta)
		var tangent := Vector2(-radial.y, radial.x)
		var tip := radial * tip_dist
		var b1 := radial * _radius + tangent * base_half
		var b2 := radial * _radius - tangent * base_half
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), spike_color)
