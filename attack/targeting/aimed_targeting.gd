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
## [method is_valid_target] answers the node-shaped question (in reach and
## passing the filter), so [SpellTargetUnion] and the AI's per-source
## enumeration see an aimed spell exactly as they see a [NodeTargeting] one.

@export var shape: AimShape
## Same flag set and meaning as [member NodeTargeting.ownership_filter].
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_filter: int = 8
@export var range_finder: EuclideanRangeFinder


func get_kind() -> TargetingKind:
	return TargetingKind.AIM


func get_range_finder() -> RangeFinder:
	return range_finder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.ownership_bit(plan.attacker) & ownership_filter == 0:
		return false
	return range_finder == null or range_finder.in_range(plan.attacker, source, candidate)


## The shape's length from [param source]: the finder's scaled reach, 0 with
## no finder (an aimed shape with no length crosses nothing).
func length(attacker: Entity, source: SkillNode) -> float:
	if range_finder == null:
		return 0.0
	return range_finder.effective_distance(attacker, source)


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
func seeds(attacker: Entity, source: SkillNode, angle: float, graph: Graph) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if shape == null or source == null or graph == null:
		return out
	var candidates: Array[SkillNode] = []
	for n: SkillNode in graph.get_skill_nodes():
		if n != source:
			candidates.append(n)
	for n in shape.crossed(source.global_position, angle, length(attacker, source), candidates):
		if attacker == null or n.ownership_bit(attacker) & ownership_filter != 0:
			out.append(n)
	return out
