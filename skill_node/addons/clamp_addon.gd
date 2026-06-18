@tool
class_name ClampAddon
extends SkillNodeAddon

## When the carrier is used as a joint in a phantom blade, weld it —
## the joint becomes rigid instead of free-pin. Design intent:
## docs/design/skill_node_addons.md#clamp.
##
## Phantom-brace trick: a weld at joint J between two arms is
## mathematically equivalent to a distance constraint between the two
## arm-tip particles. We just add such a constraint per neighbor pair.
## Reuses the existing PBD solver; no new constraint class needed.
##
## Crucially, this does NOT create a face: future area-damage code
## traverses `state.edges` (the explicit edge list), not `state.constraints`.
## Phantom braces stay invisible to it — matching the design doc's
## "rigidity only, no face" contract.
##
## Degree-2 (the typical hinge case) → 1 brace; over-constraining at
## higher degree is tolerable, PBD converges. Already-triangulated
## joints get redundant constraints; redundant ≈ no-op for PBD.

const _SPIKE_COLOR := Color(0.85, 0.85, 0.9, 0.95)

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
	var neighbors: Array[int] = []
	for e in state.edges:
		if e.x == particle_idx:
			neighbors.append(e.y)
		elif e.y == particle_idx:
			neighbors.append(e.x)
	for i in neighbors.size():
		for j in range(i + 1, neighbors.size()):
			var a := neighbors[i]
			var b := neighbors[j]
			var rest := state.positions[a].distance_to(state.positions[b])
			state.constraints.append(BladeDistanceConstraint.new(a, b, rest))


# Bracket glyph: two C-shapes facing each other, sized off the carrier.
func _draw() -> void:
	if _radius <= 0.0:
		return
	var r := _radius * 0.55
	var thickness := 3.0
	# Left bracket "[" — three short strokes.
	var lx := -r
	var rx := r
	var top := -r * 0.6
	var bot := r * 0.6
	var tab := r * 0.25
	draw_line(Vector2(lx, top), Vector2(lx, bot), _SPIKE_COLOR, thickness)
	draw_line(Vector2(lx, top), Vector2(lx + tab, top), _SPIKE_COLOR, thickness)
	draw_line(Vector2(lx, bot), Vector2(lx + tab, bot), _SPIKE_COLOR, thickness)
	# Right bracket "]"
	draw_line(Vector2(rx, top), Vector2(rx, bot), _SPIKE_COLOR, thickness)
	draw_line(Vector2(rx, top), Vector2(rx - tab, top), _SPIKE_COLOR, thickness)
	draw_line(Vector2(rx, bot), Vector2(rx - tab, bot), _SPIKE_COLOR, thickness)
