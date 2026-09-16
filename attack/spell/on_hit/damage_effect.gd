@tool
class_name DamageEffect
extends OnHitEffect

## Standard on-hit: contributes a MAGIC [DamageInstance] sized to the in-flight
## state's [member CastSpell.damage] (already scaled by propagation). The
## VFX coordinator applies it on projectile arrival.
##
## Visual origin for the produced hit is [member CastSpell.predecessor] when
## present (hops); falls back to [member CastSpell.source] for the seed so
## the first projectile flies from the cast-from node, not from nowhere.


## How the hit is denominated (see [member HitInstance.basis]): FLAT lands
## [member CastSpell.damage] as HP; PERCENT_MAX lands it as a fraction of the
## target's max hp, resolved at land by [method DamageInstance.land_on].
@export var basis: HitInstance.AmountBasis = HitInstance.AmountBasis.FLAT


func apply(lctx: LandingContext) -> void:
	var state := lctx.payload
	if state.current_node == null or state.damage <= 0.0:
		return
	var hit := DamageInstance.new()
	hit.amount = state.damage
	hit.basis = basis
	hit.type = DamageInstance.Type.MAGIC
	hit.source = state
	hit.target = state.current_node
	hit.origin = state.predecessor if state.predecessor != null else state.source
	lctx.cast.outcome.hits.append(hit)

## No [param spell] (no preview context) reads as the generic fragment;
## otherwise quotes the D-32 impact number, unscaled ([param board] null) or
## scaled by the caster's board — see [method OnHitEffect.get_description].
func get_description(spell: SpellDef = null, board: StatBoard = null) -> String:
	if spell == null:
		return "Deals magic damage."
	return "Deals %s damage." % _fmt_amount(SpellResolver.impact_damage(spell, null, board), basis)
