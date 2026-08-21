@tool
class_name OwnerFilter
extends PropagationFilter

## Allows propagation only into nodes matching the chosen ownership relation
## to the caster. Replaces the duplicated [code]only_enemy[/code] flag that
## every old [SpellPropagation] subclass carried.

enum Scope {
	## Owned by an entity the caster is HOSTILE to (null = neutral, NOT enemy).
	## Attitude, not identity: before #384 this read `owned_by != caster`, which
	## made a co-op partner's territory look like enemy ground and let every
	## damage spell chain straight through it. Targeting was migrated then;
	## propagation was missed.
	ENEMY,
	## Owned by the CASTER specifically — not a faction ally. The name predates
	## factions and is now misleading; a real caster-or-ally scope is a separate
	## decision, since renaming this breaks the ints authored in every `.tres`.
	ALLY,
	UNALLOCATED,  ## owned_by == null
	ANY,          ## no ownership filter (still excludes null only if asked)
	OWNED_ANY,    ## any non-null owner (enemy OR ally)
}

@export var scope: Scope = Scope.ENEMY


func allows(_from: SkillNode, to: SkillNode, payload: CastSpell, _ctx: PropagationContext) -> bool:
	if to == null:
		return false
	match scope:
		Scope.ENEMY:
			if to.owned_by == null:
				return false
			if payload.caster == null:
				return true  # no caster context — every owned node is fair game
			return payload.caster.attitude_to(to.owned_by) == Entity.Attitude.HOSTILE
		Scope.ALLY:
			return to.owned_by != null and to.owned_by == payload.caster
		Scope.UNALLOCATED:
			return to.owned_by == null
		Scope.OWNED_ANY:
			return to.owned_by != null
		Scope.ANY:
			return true
	return true


func get_description() -> String:
	match scope:
		Scope.ENEMY: return "Enemy-owned only."
		Scope.ALLY: return "Own-owned only."
		Scope.UNALLOCATED: return "Neutral (unallocated) only."
		Scope.OWNED_ANY: return "Allocated only."
		Scope.ANY: return ""
	return ""
