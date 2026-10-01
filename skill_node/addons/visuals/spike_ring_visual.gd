@tool
class_name SpikeRingVisual
extends AddonVisual

## The spike ring's drawing: [member spike_count] triangles standing on the
## carrier's rim, tips [member spike_overshoot] × radius beyond it, in the
## carrier's owner colour (read from the parent [SpikeRingAddon]'s carrier).

const default_color = Color.WHITE  # Color(0.95, 0.55, 0.4, 0.95)

@export_range(4, 24, 1) var spike_count: int = 12:
	set(value):
		spike_count = value
		queue_redraw()
## Derived, never authored: the spikes take the carrier's owner colour, falling
## back to its archetype colour and then to white. Deliberately NOT `@export` —
## a getter-only export shows an inspector field that discards whatever is typed
## into it, and the editor serializes the *computed* value back into the scene
## (.claude/rules/gdscript-pitfalls.md, "never write a DERIVED value back into an
## @export"). The scene carried exactly such a dead `spike_color` line until it
## was dropped alongside this.
var spike_color: Color:
	get():
		var addon := get_parent() as SkillNodeAddon
		var carrier := addon.carrier if addon != null else null
		if carrier and carrier.owned_by:
			return carrier.owned_by.color
		if carrier:
			return carrier.base_type_color
		return default_color
## How far out the spike tips reach beyond the carrier's radius.
@export_range(0.0, 1.0, 0.05) var spike_overshoot: float = 0.45:
	set(value):
		spike_overshoot = value
		queue_redraw()
## Spike base width as a fraction of the carrier's radius.
@export_range(0.05, 0.6, 0.05) var spike_base: float = 0.18:
	set(value):
		spike_base = value
		queue_redraw()


func _draw() -> void:
	if radius <= 0.0 or spike_count <= 0:
		return
	var base_half := radius * spike_base * 0.5
	var tip_dist := radius * (1.0 + spike_overshoot)
	var step := TAU / float(spike_count)
	for i in spike_count:
		var theta := i * step
		var radial := Vector2.from_angle(theta)
		var tangent := Vector2(-radial.y, radial.x)
		var tip := radial * tip_dist
		var b1 := radial * radius + tangent * base_half
		var b2 := radial * radius - tangent * base_half
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), spike_color)
