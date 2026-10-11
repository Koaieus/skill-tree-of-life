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

## [method on_removed]'s `cause` bits — bit-compatible with a subclass's own
## `@export_flags("Death", "Dealloc")` (Death=1, Dealloc=2), so a rule's
## `triggers` mask and the cause it's handed share one encoding.
const CAUSE_DEATH: int = 1
const CAUSE_DEALLOC: int = 2


## Whether this rule's rows settle at the tail of every beat — a pile that may
## topple ([SandpileSpread]). A host whose row of such a def rises tells its
## world, which drains only those piles ([method CombatWorld.note_pile]).
func settles() -> bool:
	return false


## Once per tick of [param field]'s status: the transfers to land, in order.
func on_tick(_field: StackField) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


## [param removed] is the whole beat's union, judged against [param field]'s
## state from before removal; a receiver must be outside it. [param cause] is
## ONE of [constant CAUSE_DEATH] / [constant CAUSE_DEALLOC] — never a
## combination; a rule gates it against its own trigger flags. The transfers
## to land, in order.
func on_removed(_field: StackField, _removed: Array[NodeCombat], _cause: int) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


## One player-facing sentence for how this rule moves stacks, in the rule's
## own numbers ([NumFmt]) — the concept card's Spread section asks it, never
## re-derives it. A rule with nothing worth saying returns `""` and the
## section is omitted. Not abstract: a bare test subclass stays valid.
func describe() -> String:
	return ""


## "killed", "released", or "killed or released" for a [param causes] mask of
## [constant CAUSE_DEATH] / [constant CAUSE_DEALLOC] bits; `""` for none.
static func cause_phrase(causes: int) -> String:
	var words: PackedStringArray = []
	if causes & CAUSE_DEATH:
		words.append("killed")
	if causes & CAUSE_DEALLOC:
		words.append("released")
	return " or ".join(words)


## A QUOTE of what this rule would hand [param node]'s neighbours were it
## removed now, for [param share] of its raw row — without removing it and
## without any remainder burn: every transfer's `from` is [param node] and
## its `to` a receiver. The caller lands the `to` side only (as hits —
## [FluxEffect]); handing the list to [SpreadApplier] would debit the source.
## Default: nothing to copy.
func copy_out(_field: StackField, _node: NodeCombat, _share: float) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]
