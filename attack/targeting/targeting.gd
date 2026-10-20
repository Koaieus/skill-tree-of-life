@tool
@abstract
class_name Targeting
extends Resource

## How an [AttackPlan] (or [SpellDef]) collects its target. Encapsulates
## "what counts as valid" and "how to enumerate candidates" — orthogonal to
## the effect payload. Reusable across modes: a SingleHostileNodeTargeting
## works the same whether the carrier is a melee blade target, a ranged
## attack, or a damage spell.
##
## Subclasses override [method is_valid_target]. Reach and ownership are base
## facts: [member range_finder] bounds how far the targeting reaches (null =
## unlimited) and [member ownership_filter] who it may pick.
## [method valid_targets] gathers once from the finder and filters by
## ownership; only a finder-less targeting walks the live graph. An EDGE or
## SELF subclass that bounds nothing leaves the finder null, and one with a
## different candidate notion overrides [method valid_targets] entirely.


## Kinds of input the targeting consumes: a node pick for NODE, an edge for
## EDGE, an aim angle dragged from the cast-from node for AIM
## ([AimedTargeting]), nothing for SELF (the source IS the target). No input
## path routes on this yet.
enum TargetingKind {
	NODE,
	EDGE,
	AIM,
	SELF,
}


## Four mutually exclusive buckets (#384, see [method SkillNode.ownership_bit]):
## Neutral 1 / Mine 2 / Ally 4 / Hostile 8. `Friendly`/`Allocated`/`Any` are
## composites, not extra bits — they let the inspector's flag checkboxes reach
## a common OR-of-bits directly instead of hand-combining Mine+Ally each time.
##
## [OwnerFilter] (spell propagation) takes the SAME flag set: who a spell may
## be aimed at and who it may chain into are one vocabulary. Keep them in step.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_filter: int = 8
## The reach model; null means unlimited reach. A subclass that needs a
## narrower finder type refuses the rest by overriding [method _set_range_finder].
@export var range_finder: RangeFinder: set = _set_range_finder


## Input flavor — subclasses override only when their kind differs from
## the NODE default.
func get_kind() -> TargetingKind:
	return TargetingKind.NODE


## Player-facing "who/what this can hit" line for [SpellTooltip]'s Cast
## section (#764). Empty base — nothing worth saying about the abstract
## contract. Subclasses override; see [method NodeTargeting.get_description].
func get_description() -> String:
	return ""


## This targeting's reach model, or null when it bounds nothing — the ONE way
## to ask a [Targeting] how far it reaches.
func get_range_finder() -> RangeFinder:
	return range_finder


## Setter hook for [member range_finder]; a named method so a subclass can
## narrow what it accepts.
func _set_range_finder(value: RangeFinder) -> void:
	range_finder = value


## True iff [param candidate] is an acceptable target given [param source]
## under [param plan]. The click handler routes a selected node here.
@abstract func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool


## All currently-valid target SkillNodes given the plan and source. Used
## by the highlight overlay to paint IN_RANGE candidates and by AI to
## enumerate options.
##
## ONE gather sweep, not one per-pair query per board node (#942): for a hop
## finder each [method is_valid_target] call is a full AStar, while
## [method RangeFinder.gather] answers the whole question in one bounded BFS
## (hops) or one scan (euclid); the ownership filter then runs over that reach
## map, the same gather-then-filter shape as [SpellTargetUnion]. This MUST
## agree with [method is_valid_target] as a set — pinned by test_targeting.gd's
## equivalence tests — which holds because the sweep reads the same whole-board
## `graph.navigator` mirror `in_range` does, with the attacker passed so
## `effective_*` reach scaling folds in identically.
##
## No finder means unlimited reach, so there is nothing to sweep: the per-node
## walk via [method is_valid_target] is the right (and cheap) path then.
func valid_targets(plan: AttackPlan, source: SkillNode) -> Array[SkillNode]:
	if range_finder == null:
		return _filter_skill_nodes(plan, source)
	var result: Array[SkillNode] = []
	if source == null or plan == null or plan.attacker == null or plan.attacker.navigator == null:
		return result
	var graph := plan.attacker.navigator.graph
	if graph == null or graph.navigator == null:
		return result
	var reach: Dictionary[SkillNode, float] = range_finder.gather(source, graph.navigator, plan.attacker)
	for candidate: SkillNode in reach:
		if candidate.ownership_bit(plan.attacker) & ownership_filter != 0:
			result.append(candidate)
	return result


func _filter_skill_nodes(plan: AttackPlan, source: SkillNode) -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	if plan == null or plan.attacker == null or plan.attacker.navigator == null:
		return result
	var graph := plan.attacker.navigator.graph
	if graph == null:
		return result
	for sn in graph.get_skill_nodes():
		if is_valid_target(plan, source, sn):
			result.append(sn)
	return result
