@tool
class_name CureEffect
extends SpellOnHitEffect

## A cleanse on-hit: the landing's [member CastSpell.damage] is the DOSE (the
## same figure [HealEffect] heals by — cure is 1:1 with the hit). [member cure]
## prices it ([method Cure.plan]); the dose spent is taken out of
## [member CastSpell.damage] IN PLACE and one [CureInstance] carries the exact
## per-status counts (core part first, see [Cure]) plus
## [code]Σcleared × heal_per_stack[/code] HP, healed on the node for both parts.
##
## [b]Drain in place.[/b] On-hit effects run before departure, so the leftover
## is what the next hop inherits — the [ScaleDamageEffect] precedent. Pair it
## with a [NeedSplitSpread] holding the SAME [Cure] and a [SumDamageReducer]
## so the leftover is split by need and conserved where branches meet.
##
## The counts are decided HERE, on the world the walk reads (stacks through
## [method LandingContext.stacks_of], never the live node); the instance
## applies them verbatim at land. Nothing cleared emits nothing and leaves the
## dose whole.

## The table: what this cleanse cures and at what price. Shared by reference
## with the spell's [NeedSplitSpread]; null makes the effect inert.
@export var cure: Cure = null
## HP healed per stack cleared, summed over every status. Linear, not the
## triangle sum. 1.0 matches poison's damage per stack.
@export_range(0, 10, 0.1) var heal_per_stack: float = 1.0
@export var terms: Array[CleanseTerm] = []


func _apply_spell(lctx: LandingContext) -> void:
	var state := lctx.payload
	if cure == null or state == null or state.current_node == null or state.damage <= 0.0:
		return
	var plan := cure.plan(state.current_node, state.damage, lctx)
	var core_cleared: Dictionary = plan.core_cleared
	var cleared: Dictionary = plan.cleared
	if cleared.is_empty() and core_cleared.is_empty():
		return
	var hit := CureInstance.new()
	var total := 0.0
	for def: StatusDef in core_cleared:
		hit.add(def, core_cleared[def], true)
		total += core_cleared[def]
	for def: StatusDef in cleared:
		hit.add(def, cleared[def])
		total += cleared[def]
	hit.heal = total * heal_per_stack
	hit.source = state
	hit.target = state.current_node
	hit.origin = state.predecessor if state.predecessor != null else state.source
	hit.read_node = state.source
	lctx.cast.outcome.hits.append(hit)
	state.damage = maxf(state.damage - float(plan.spent), 0.0)


## "Cures Poison, Bleeding (dose = hit)." — the names come from the table, in
## table order; the per-stack heal follows when it is non-zero.
func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var names: Array[String] = []
	if cure != null:
		for e in cure.entries:
			if e != null and e.status != null:
				names.append(e.status.display_name if e.status.display_name != "" else String(e.status.id))
	var what := ", ".join(names) if not names.is_empty() else "statuses"
	var line := "Cures %s (dose = hit)" % what
	if heal_per_stack > 0.0:
		line += ", healing %s per stack cleared" % NumFmt.num(heal_per_stack)
	return line + "."
