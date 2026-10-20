@tool
class_name PayWorthTerm
extends CleanseTerm

## The cleansed node PAYS what the cleared stacks were worth: one TRUE, FLAT
## [CleansePriceInstance] on it of `Σ def.cleanse_worth(holder, count) ×
## scale`, appended after the [CureInstance] so it lands after the clears.
## The holder is the slice the stacks came off — the landed node's owner's
## entity row for an `on_core` entry, else the node — looked up in the cast's
## world, never the live node. The price never draws its own crit: a crit on
## the cleanse multiplies the stacks cleared, and the price follows them.
## Zero total appends nothing.

## Multiplier on the summed worth.
@export_range(0, 10, 0.1) var scale: float = 1.0


func settle(hit: CureInstance, lctx: LandingContext) -> void:
	if hit.target == null or lctx == null or lctx.cast == null:
		return
	var slice: NodeCombat = lctx.cast.world.combat_for(hit.target)
	if slice == null:
		return
	var total := 0.0
	for i in hit.defs.size():
		var def := hit.defs[i]
		if def == null:
			continue
		var core := i < hit.on_core.size() and hit.on_core[i] != 0
		var holder: Object = slice
		if core:
			holder = slice.owner()
		if holder != null:
			total += def.cleanse_worth(holder, hit.cleared[i])
	total *= scale
	if total <= 0.0:
		return
	var price := CleansePriceInstance.new()
	price.type = DamageInstance.Type.TRUE
	price.basis = HitInstance.AmountBasis.FLAT
	price.amount = total
	price.source = hit.source
	price.target = hit.target
	price.origin = hit.origin
	price.read_node = hit.read_node
	lctx.cast.outcome.hits.append(price)


func describe() -> String:
	if scale <= 0.0:
		return ""
	return "the node pays the cleared stacks' worth as true damage"
