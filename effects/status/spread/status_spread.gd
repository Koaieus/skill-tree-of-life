@abstract
class_name StatusSpread
extends Resource

## How a status's stacks move between hosts — the swappable signature in
## [member StatusDef.spread]. Shared and stateless like the def that holds it:
## no per-node state ever lives here. A rule is PURE: a [StackField] goes in,
## an ordered [StackTransfer] list comes out, and [SpreadApplier] lands it.
## Members are conserving or dissipative (a null `to` burns), never creating;
## `stable_id` never decides who gets what. Both hooks default to "no
## transfers".

## Which neighbours stacks may flow to, as [method SkillNode.ownership_bit]
## bits seen by the HOST node's owner — the same flag set, verbatim, as
## [member NodeTargeting.ownership_filter]. Default Mine.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_mask: int = 2


## Once per tick of [param field]'s status: the transfers to land, in order.
func on_tick(_field: StackField) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


## [param removed] just lost the status (its row is gone): the transfers to
## land, in order.
func on_removed(_field: StackField, _removed: NodeCombat) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]
