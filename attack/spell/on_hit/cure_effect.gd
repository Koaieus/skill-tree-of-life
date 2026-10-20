@tool
class_name CureEffect
extends SpellOnHitEffect

## A cleanse on-hit: the landing's [member CastSpell.damage] is the DOSE (the
## same figure [HealEffect] heals by — cure is 1:1 with the hit). [member cure]
## prices it ([method Cure.plan]); the dose spent is taken out of
## [member CastSpell.damage] IN PLACE and one [CureInstance] carries the exact
## per-status counts (core part first, see [Cure]). What the clears buy or
## cost is [member terms]' call, settled on that hit after it is appended.
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
## What this cleanse does with the stacks it cleared, in order
## ([method CleanseTerm.settle_all]) — a [HealPerStackTerm] heals, a
## [PayWorthTerm] charges their worth. Empty is a free cleanse.
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
	for def: StatusDef in core_cleared:
		hit.add(def, core_cleared[def], true)
	for def: StatusDef in cleared:
		hit.add(def, cleared[def])
	hit.source = state
	hit.target = state.current_node
	hit.origin = state.predecessor if state.predecessor != null else state.source
	hit.read_node = state.source
	lctx.cast.outcome.hits.append(hit)
	CleanseTerm.settle_all(terms, hit, lctx)
	state.damage = maxf(state.damage - float(plan.spent), 0.0)


## "Cures Poison, Bleeding (dose = hit)." — the names come from the table, in
## table order; each term's fragment follows ([method CleanseTerm.describe_all]).
func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var names: Array[String] = []
	if cure != null:
		for e in cure.entries:
			if e != null and e.status != null:
				names.append(e.status.display_name if e.status.display_name != "" else String(e.status.id))
	var what := ", ".join(names) if not names.is_empty() else "statuses"
	var parts: Array[String] = ["Cures %s (dose = hit)" % what]
	parts.append_array(CleanseTerm.describe_all(terms))
	return ", ".join(parts) + "."
