@tool
class_name HealPerStackTerm
extends CleanseTerm

## The clears buy HP: `Σcleared × per_stack` healed on the cleansed node,
## over every status and both the core and node parts. Linear, not the
## triangle sum.

## HP healed per stack cleared. 1.0 matches poison's damage per stack.
@export_range(0, 10, 0.1) var per_stack: float = 1.0


func settle(hit: CureInstance, _lctx: LandingContext) -> void:
	hit.heal += CleanseTerm.cleared_total(hit) * per_stack


func describe() -> String:
	if per_stack <= 0.0:
		return ""
	return "healing %s per stack cleared" % NumFmt.num(per_stack)
