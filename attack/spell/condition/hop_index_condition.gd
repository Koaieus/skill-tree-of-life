@tool
class_name HopIndexCondition
extends LandingCondition

## True when the landing's [member CastSpell.hop_index] lies in
## [member min_hop]..[member max_hop] (inclusive; the seed is hop 0). As a
## [member SpellDef.rider_when], [code]max_hop = 0[/code] lands the intake load
## at the struck node only; as an effect's [member OnHitEffect.when],
## [code]min_hop = 1[/code] keeps it off the seed.

## The lowest hop that passes.
@export_range(0, 10, 1, "or_greater") var min_hop: int = 0
## The highest hop that passes; -1 = unbounded.
@export_range(-1, 10, 1, "or_greater") var max_hop: int = -1


func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.payload == null:
		return false
	var hop := lctx.payload.hop_index
	return hop >= min_hop and (max_hop < 0 or hop <= max_hop)


func get_description() -> String:
	if max_hop == 0:
		return "on the struck node"
	if max_hop < 0:
		return "from hop %d on" % min_hop if min_hop > 0 else ""
	return "on hops %d to %d" % [min_hop, max_hop]
