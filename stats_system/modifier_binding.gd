class_name ModifierBinding

## How a stat modifier is *held* by an entity — its binding/holder. Distinct
## from the modifier's op-type ([enum StatModifier.Operation]: ADD_BASE /
## INCREASE / MULTIPLY / SET), which is a different axis entirely.
##
## Canonical domain taxonomy referenced by [signal Events.stat_modifier_changed]
## and the [FloaterDirector]. Deliberately NOT a field on [StatModifier] yet —
## nothing reads binding behaviorally (node-local is modelled by [member SkillNode.node_board];
## core-vs-node is derivable from the attachment site). Add a typed field of
## this enum to StatModifier only if a transfer-rule becomes load-bearing.

enum Kind {
	NODE,        ## Normal: lent by an allocated [SkillNode]; transfers to the entity board; removed on dealloc.
	CORE,        ## Held by the entity's mobile core (CoreClass / SkillDust loot).
	NODE_LOCAL,  ## Sits on a node; does NOT transfer to the board, but counts for node-local stat queries.
}
