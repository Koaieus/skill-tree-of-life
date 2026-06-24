@tool
class_name OwnerFilter
extends PropagationFilter

## Allows propagation only into nodes matching the chosen ownership relation
## to the caster. Replaces the duplicated [code]only_enemy[/code] flag that
## every old [SpellPropagation] subclass carried.

enum Scope {
	ENEMY,        ## owned by an entity that isn't the caster (null = neutral, NOT enemy)
	ALLY,         ## owned by the caster
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
			return to.owned_by != null and to.owned_by != payload.caster
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
