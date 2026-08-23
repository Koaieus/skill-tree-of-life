@tool
class_name OwnerFilter
extends PropagationFilter

## Allows propagation only into nodes matching the chosen ownership relation
## to the caster. Replaces the duplicated [code]only_enemy[/code] flag that
## every old [SpellPropagation] subclass carried.
##
## Speaks [method SkillNode.ownership_bit]'s bucket vocabulary (#384) — the
## SAME `@export_flags` set [member NodeTargeting.ownership_filter] uses, so
## "who a spell may chain into" and "who a spell may be aimed at" are one
## vocabulary rather than two enums that drift. Before this, `Scope` was a
## parallel enum whose ENEMY/ALLY meant `owned_by != caster` / `== caster` —
## entity identity, from before factions existed — so a chain seeded on a real
## enemy hopped straight into a co-op partner's territory, and no value could
## express "me *and* my camp" at all.
##
## Every old scope maps onto a flag exactly: ENEMY→Hostile(8), ALLY→Mine(2),
## UNALLOCATED→Neutral(1), OWNED_ANY→Allocated(14), ANY→Any(15). No `.tres`
## authored `scope`, so all seven shipped spells inherit the new Hostile
## default unchanged.


## Neutral 1 / Mine 2 / Ally 4 / Hostile 8, OR-ed. The composites are the
## useful ones: `Friendly` (6) is "mine or my camp's" — the scope that was
## unreachable before — and `Allocated` (14) is any owned node. Note `Ally` (4)
## alone means the camp WITHOUT the caster's own nodes; a heal almost always
## wants `Friendly`.
##
## Flags, not an enum, because "chain through enemies and unallocated ground"
## (9) is a real spell shape a single-select scope can't say. The hint string
## is duplicated from [NodeTargeting] because Godot can't take a `const` in an
## `@export_flags` annotation — the SEMANTICS live in one place
## ([method SkillNode.ownership_bit]), which is the part that must not fork.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15")
var ownership_filter: int = 8


func allows(_from: SkillNode, to: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> bool:
	if to == null:
		return false
	# Asked of the CAST'S WORLD, not of the node (#536) — the real node still
	# reads as allocated after this same cast killed it, and admitting a corpse
	# is the bug that closed. A null caster reads HOSTILE out of `ownership_bit`,
	# matching the old no-caster-context behaviour (every owned node stayed fair
	# game).
	return ctx.ownership_bit_of(to) & ownership_filter != 0


## Composed from the set bits rather than matched against the named combos —
## the flags are freely OR-able, so a spell authored as Hostile|Neutral (9)
## must not describe itself as a blank string.
func get_description() -> String:
	if ownership_filter & 15 == 15:
		return ""  # everything — nothing worth saying
	var parts: Array[String] = []
	if ownership_filter & SkillNode.Ownership.MINE:
		parts.append("own")
	if ownership_filter & SkillNode.Ownership.ALLY:
		parts.append("allied")
	if ownership_filter & SkillNode.Ownership.HOSTILE:
		parts.append("enemy")
	if ownership_filter & SkillNode.Ownership.NEUTRAL:
		parts.append("unallocated")
	if parts.is_empty():
		return "Nothing (no ownership bits set)."
	return "%s-owned only." % " or ".join(parts)
