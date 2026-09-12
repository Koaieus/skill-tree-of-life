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
## Subclasses override [method is_valid_target]; the default
## [method valid_targets] iterates the live graph and filters via that
## predicate, which is enough for NODE-kind targeting. EDGE / POSITION
## subclasses can override [method valid_targets] entirely.


## Kinds of input the targeting consumes. PlayerInputController routes
## node-clicks for NODE/EDGE, world-clicks for POSITION, and skips
## targeting input entirely for SELF (the source IS the target).
enum TargetingKind {
	NODE,
	EDGE,
	POSITION,
	SELF,
}


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
##
## Virtual rather than a base `@export` because reach is NOT universal: an
## EDGE- or SELF-kind targeting has no finder to hold. Before this existed the
## question was asked three different ways — a reflective
## `targeting.get(&"range_finder")`, a bare `.range_finder` property read that
## would crash on the first non-[NodeTargeting] subclass, and an
## `as NodeTargeting` cast — which is three implementations of one contract
## (`.claude/rules/scene-composition.md`'s sibling rule: no parallel mirrors).
func get_range_finder() -> RangeFinder:
	return null


## True iff [param candidate] is an acceptable target given [param source]
## under [param plan]. The click handler routes a selected node here.
@abstract func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool


## All currently-valid target SkillNodes given the plan and source. Used
## by the highlight overlay to paint IN_RANGE candidates and by AI to
## enumerate options. Default iterates the live graph and filters via
## [method is_valid_target].
func valid_targets(plan: AttackPlan, source: SkillNode) -> Array[SkillNode]:
	return _filter_skill_nodes(plan, source)


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
