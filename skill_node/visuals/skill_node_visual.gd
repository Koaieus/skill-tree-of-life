@tool
class_name SkillNodeVisual
extends Node2D
## Base class for the SkillNode-visuals-v2 component family (milestone #16,
## see docs/design/handoff_skill_nodes_visuals/). Each component (inner disk,
## weld symbol, ring wall, ...) subclasses this or [SkillNodeRingVisual],
## exposes its own @export knobs following the `set(v): field = v;
## queue_redraw()` pattern, and draws itself in `_draw()`.
##
## ## The identity contract
##
## Every component in this family is *provided* the node's [member radius] and
## its two identity colors — [member entity_tint], [member archetype_tint] —
## plus whether the node is [member allocated]. The composite
## (node_visuals_composite.gd) is the SOLE authority on all four: it pushes
## them into every child uniformly, so a component can never be added and then
## silently forgotten in a fan-out (the bug that left RimBonuses' glow dial
## rendering in entity color long after rims went archetype-colored).
##
## Children then consume these **freely**, as they see fit — that's the point
## of provide/inject rather than a rigid mapping. A component may read one, the
## other, both, or neither; it may mix either against a private color of its
## own (RimRing blends its bronze metal toward `archetype_tint`; InnerDisk
## blends grey toward `entity_tint`). Private colors stay private @exports on
## the child — "these rune glyphs are gold regardless" is a legitimate design,
## and it doesn't need the base class's permission. What the base class
## guarantees is only that the two identities are *reachable* and *in sync*, so
## flipping a component from one to the other is a one-line edit, not a
## re-plumbing.

@export_range(0.0, 128.0, 0.5) var radius: float = 32.0:
	set(value):
		radius = value
		queue_redraw()

## The allocating entity's color ("this is MINE"). Provided by the composite.
@export var entity_tint: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		entity_tint = value
		_on_identity_changed()

## The node's persistent type identity — red-ish STR, green-ish DEX, ... .
## Provided by the composite; legible whether or not the node is owned.
@export var archetype_tint: Color = Color(0.65, 0.67, 0.72):
	set(value):
		archetype_tint = value
		_on_identity_changed()

## Whether the owning node is allocated. Provided by the composite.
@export var allocated: bool = false:
	set(value):
		allocated = value
		_on_identity_changed()


## Virtual hook: fires when any identity input above changes. The default
## redraws; components whose identity feeds a shader override this to resync
## their uniforms instead.
func _on_identity_changed() -> void:
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
