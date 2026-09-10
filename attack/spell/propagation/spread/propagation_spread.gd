@tool
@abstract
class_name PropagationSpread
extends Resource

## Selects WHERE one landing's expansion goes, given the already-narrowed
## candidate set — and nothing else (#852). A spread returns
## [PropagationPick]s: a destination, the damage share that arc carries, and
## any per-hop facts the arrival side needs stamped on the child. It never
## constructs a [CastSpell], never does damage math, never touches
## [member CastSpell.hops_remaining]; [method PropagationConfig.mint] turns
## each pick into the child and is the one place a child is built.
##
## The three departure stages, in order: filter [b]narrows[/b]
## ([method PropagationFilter.narrow]) → spread [b]selects[/b] ([method select])
## → config [b]mints[/b] ([method PropagationConfig.mint]).


## One pick per child to mint, in the order they should be minted (a stable
## order is what keeps the crit stream deterministic across peers).
## [param eligible] is what the filter left; [param payload] is read-only here.
@abstract func select(
		current: SkillNode,
		eligible: Array[SkillNode],
		payload: CastSpell,
		ctx: PropagationContext) -> Array[PropagationPick]


func get_description() -> String:
	return ""
