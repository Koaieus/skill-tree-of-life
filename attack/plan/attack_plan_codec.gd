class_name AttackPlanCodec
extends RefCounted

## Mode -> concrete type dispatch for [AttackPlan] deserialization (#511).
##
## Separate from [AttackPlan] for the same reason [CommandCodec] is separate
## from [Command]: `MeleeAttackPlan extends AttackPlan` while `AttackPlan`
## names `MeleeAttackPlan` is a parse-time cycle in GDScript. The per-type
## `static from_dict` stays on each plan where it belongs. If you see "Could
## not find type MeleeAttackPlan" here, that is the cycle talking, not a stale
## class cache — do not reach for `mise run refresh`.
##
## Encoding needs no dispatch at all: `plan.to_dict(graph)`.
##
## [param graph] is not optional anywhere here. A plan's wire form is nothing
## but ids, and only a [Graph] can turn those back into the live
## [SkillNode]s / [Entity] the rebuilt plan needs.


## Rebuild a plan from its wire form. Returns null on an unknown or missing
## mode rather than half-building something a launch would then act on.
static func from_dict(d: Dictionary, graph: Graph) -> AttackPlan:
	if d.is_empty():
		return null
	match int(d.get("mode", BattleSystem.AttackMode.NONE)):
		BattleSystem.AttackMode.MELEE:
			return MeleeAttackPlan.from_dict(d, graph)
		BattleSystem.AttackMode.RANGED:
			return RangedAttackPlan.from_dict(d, graph)
		BattleSystem.AttackMode.MAGIC:
			return MagicAttackPlan.from_dict(d, graph)
	push_warning("AttackPlanCodec: unknown attack mode %s" % d.get("mode"))
	return null
