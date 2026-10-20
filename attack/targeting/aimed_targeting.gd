@tool
class_name AimedTargeting
extends Targeting

## A spell aimed in a direction rather than at a node (#1495): from the
## cast-from node, [member shape] is pointed at an angle and every node it
## crosses that passes [member ownership_filter] becomes a seed of its own
## ([method SpellResolver.resolve_seeds]). The shape's length is
## [member range_finder]'s reach, scaled through [SpellRangeRules] like any
## euclidean cast range — the aim carries an angle and never a length.
##
## Every direction the shape can point covers exactly the finder's disc, so the
## node-shaped questions ([method is_valid_target], the base gather-then-filter
## [method Targeting.valid_targets], [SpellTargetUnion]'s reach sets the AI
## reads) see an aimed spell exactly as they see a [NodeTargeting] one.

@export var shape: AimShape


func get_kind() -> TargetingKind:
	return TargetingKind.AIM


## [member Targeting.range_finder], typed: an aimed shape's length is a
## euclidean distance, so only a [EuclideanRangeFinder] is ever held.
func euclid_finder() -> EuclideanRangeFinder:
	return range_finder as EuclideanRangeFinder


## Refuses a non-euclidean finder (a hop count has no length to draw).
func _set_range_finder(value: RangeFinder) -> void:
	if value != null and not (value is EuclideanRangeFinder):
		push_error("AimedTargeting needs a EuclideanRangeFinder, got %s" % value)
		return
	range_finder = value


func _validate_property(property: Dictionary) -> void:
	if property.name == "range_finder":
		property.hint_string = "EuclideanRangeFinder"


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.ownership_bit(plan.attacker) & ownership_filter == 0:
		return false
	return range_finder == null or range_finder.in_range(plan.attacker, source, candidate)


## The shape's length from [param source]: the finder's scaled reach, 0 with
## no finder (an aimed shape with no length crosses nothing).
func length(attacker: Entity, source: SkillNode) -> float:
	var finder := euclid_finder()
	if finder == null:
		return 0.0
	return finder.effective_distance(attacker, source)


## What the aim looks like from [param source] at [param angle]: the finder's
## reach ring plus the shape itself, drawn to its full length. No aim yet
## (NAN) → the ring alone.
func get_visual(attacker: Entity, source: SkillNode, angle: float) -> RangeVisual:
	var visual: RangeVisual = range_finder.get_visual(attacker, source) if range_finder != null else null
	if visual == null:
		visual = RangeVisual.new()
	if shape != null and source != null and not is_nan(angle):
		visual.shapes.append(RangeVisual.AimEntry.new(
				source.global_position, angle, length(attacker, source), shape))
	return visual


## Every node the shape crosses aimed at [param angle] from [param source],
## nearest-first, that passes [member ownership_filter]. The source itself is
## never a seed: its disc contains the origin, so every shape would cross it.
## Candidates come from the graph's grid ([method Graph.spatial_candidates])
## around [method AimShape.reach]; [method AimShape.crossed] stays the exact
## decider, so the grid only narrows — a miss is a bug, never an extra.
func seeds(attacker: Entity, source: SkillNode, angle: float, graph: Graph) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if shape == null or source == null or graph == null:
		return out
	var len := length(attacker, source)
	var candidates := graph.spatial_candidates(source.global_position, shape.reach(len))
	candidates.erase(source)
	for n in shape.crossed(source.global_position, angle, len, candidates):
		if attacker == null or n.ownership_bit(attacker) & ownership_filter != 0:
			out.append(n)
	return out
