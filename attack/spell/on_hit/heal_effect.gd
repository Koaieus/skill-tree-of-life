@tool
class_name HealEffect
extends OnHitEffect

## Healing on-hit: contributes a [HealInstance] sized to the in-flight
## state's [member CastSpell.damage] (yes, `DAMAGE`!) already scaled by propagation.
## The VFX coordinator applies it on projectile arrival. Renamed from
## `HealingEffect` (#381) to parallel `DamageEffect`.
##
## Visual origin for the produced hit is [member CastSpell.predecessor] when
## present (hops); falls back to [member CastSpell.source] for the seed so
## the first projectile flies from the cast-from node, not from nowhere.

## How the heal is denominated (see [member HitInstance.basis]): FLAT lands
## [member CastSpell.damage] as HP; PERCENT_MAX lands it as a fraction of the
## target's max hp, resolved at land by [method HealInstance.land_on].
@export var basis: HitInstance.AmountBasis = HitInstance.AmountBasis.FLAT


func apply(lctx: LandingContext) -> void:
	var state := lctx.payload
	if state.current_node == null or state.damage <= 0.0:
		return
	var heal := HealInstance.new()
	heal.amount = state.damage
	heal.basis = basis
	heal.source = state
	heal.target = state.current_node
	heal.origin = state.predecessor if state.predecessor != null else state.source
	lctx.cast.outcome.hits.append(heal)

## Same D-32 number as [method DamageEffect.get_description] — heal amount
## reuses [code]spell_damage[/code] (see this file's top docstring: "yes,
## DAMAGE!") so the same [method SpellResolver.impact_damage] call applies.
func get_description(spell: SpellDef = null, board: StatBoard = null) -> String:
	if spell == null:
		return "Heals the node it lands on."
	return "Heals %s." % _fmt_amount(SpellResolver.impact_damage(spell, null, board), basis)
