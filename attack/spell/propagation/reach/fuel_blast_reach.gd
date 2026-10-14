@tool
class_name FuelBlastReach
extends PropagationReach

## Firecracker's reach: every landing is a blast, and the blast picks the next
## wave. The candidates are every node whose disc touches a circle of
## [method radius_at] around the landed node — edges play no part — minus the
## landed node itself, in stable-id order. Ownership is the config's filter's
## call and the visit cap the resolver's, never this.
##
## Fuel is the cast's [member PropagationContext.load] of [member fuel_aspect]
## less [member fuel_per_jump] per hop, so it shrinks wave by wave and the
## radius with it; at fuel 0 the radius is 0, no candidate, and the cast ends.
##
## Contract: fuel is a function of the WAVE (the payload's `hop_index`), never
## carried per front, so fronts merged on one node all depart with the same
## fuel and the reducer's pick cannot change it. A per-front fuel (a front
## that burns more than its siblings) would need a max-fuel merge, or the
## reducer silently picks one front's fuel at random.

## The aspect whose load is the fuel.
@export var fuel_aspect: StringName = &"explosive"
## Fuel burnt per hop, flat.
@export_range(0, 10, 1, "or_greater") var fuel_per_jump: int = 1
## Blast radius per point of fuel, in scene pixels.
@export_range(0.0, 256.0, 1.0, "or_greater") var px_per_fuel: float = 32.0
## The widest blast, however much fuel is infused.
@export_range(0.0, 2048.0, 1.0, "or_greater") var max_radius: float = 384.0


## Fuel left at [param hop_index] for a cast carrying [param load].
func fuel_at(load: Dictionary, hop_index: int) -> int:
	return int(load.get(fuel_aspect, 0)) - hop_index * fuel_per_jump


## The blast radius a landing at [param hop_index] departs with; 0 = none.
func radius_at(load: Dictionary, hop_index: int) -> float:
	return clampf(px_per_fuel * fuel_at(load, hop_index), 0.0, max_radius)


func candidates(lctx: LandingContext) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if lctx == null or lctx.node == null or lctx.cast == null or lctx.cast.graph == null or lctx.payload == null:
		return out
	var radius := radius_at(lctx.cast.load, lctx.payload.hop_index)
	if radius <= 0.0:
		return out
	var graph := lctx.cast.graph
	out = EuclideanRangeFinder.nodes_within(lctx.node, graph.get_skill_nodes(), radius)
	out.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return graph.get_stable_id(a) < graph.get_stable_id(b))
	return out


func get_description() -> String:
	return "Blasts %s units per %s, shrinking each hop" % [NumFmt.num(px_per_fuel), fuel_aspect]
