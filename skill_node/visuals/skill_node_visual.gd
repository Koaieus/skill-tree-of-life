@tool
class_name SkillNodeVisual
extends Node2D
## Base class for the SkillNode-visuals-v2 component family (milestone #16,
## see docs/design/handoff_skill_nodes_visuals/). Each component (inner disk,
## weld symbol, ring wall, ...) subclasses this or [SkillNodeRingVisual],
## exposes its own @export knobs following the `set(v): field = v;
## queue_redraw()` pattern, and draws itself in `_draw()`.
##
## Lives alongside the existing base_circle/hover_ring render path, not in
## place of it — cutover is a future, separate decision.

## Optional back-reference to the owning SkillNode, for a future cutover from
## the legacy base_circle/hover_ring render path (see
## .claude/rules/skill-node-visuals.md). Left null when previewed standalone
## in the sandbox panel.
@export var skill_node: SkillNode = null

@export_range(0.0, 128.0, 0.5) var radius: float = 32.0:
	set(value):
		radius = value
		queue_redraw()


## Virtual hook: subclasses override to react to an externally-driven radius
## change (e.g. forwarded from a parent composite) beyond the plain setter.
func configure(new_radius: float) -> void:
	radius = new_radius


## Point on the circle of the given radius at polar angle theta (radians).
static func polar_point(r: float, theta: float) -> Vector2:
	return Vector2.from_angle(theta) * r


## Evenly-spaced angles (radians) around a circle. `count <= 0` -> empty.
static func polar_steps(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if count <= 0:
		return out
	var step := TAU / float(count)
	for i in count:
		out.append(i * step)
	return out
