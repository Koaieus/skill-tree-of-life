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
