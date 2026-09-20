@tool
class_name ApplyStatusEffect
extends OnHitEffect

## Applies a [StatusDef] on-hit: contributes a [StatusInstance] carrying
## [member def] / [member power] (#878, #868 hub). Unlike [DamageEffect] /
## [HealEffect], the number is this effect's OWN export rather than a read of
## [member CastSpell.damage] — a status spell's magnitude is authored on the
## applier, not derived from the propagated damage figure. Compose alongside
## [DamageEffect] on the same [SpellDef] for a "little damage, applies a
## status" spell (owner's Blindness/Poison ask, #868).
##
## Visual origin for the produced hit is [member CastSpell.predecessor] when
## present (hops); falls back to [member CastSpell.source] for the seed —
## same rule as every other on-hit effect, so the first projectile still
## flies from the cast-from node.

@export var def: StatusDef = null
@export var power: float = 1.0


func apply(lctx: LandingContext) -> void:
	var state := lctx.payload
	if state == null or state.current_node == null or def == null:
		return
	var status := StatusInstance.new()
	status.def = def
	status.power = power
	# The potency read at land (#963) is the caster's board.
	status.attacker = lctx.cast.caster
	status.source = state
	status.target = state.current_node
	status.origin = state.predecessor if state.predecessor != null else state.source
	lctx.cast.outcome.hits.append(status)


## Per #764's contract: a null [param spell] (no preview context) still
## returns a description, just without needing one — [member power] is
## already this effect's own authored number, not a formula input.
func get_description(_spell: SpellDef = null, _board: StatBoard = null) -> String:
	if def == null:
		return "Applies a status."
	var name := def.display_name if not def.display_name.is_empty() else String(def.id)
	return "Applies %s (%s)." % [name, _fmt_num(power)]
