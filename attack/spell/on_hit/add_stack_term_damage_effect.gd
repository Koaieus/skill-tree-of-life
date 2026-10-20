@tool
class_name AddStackTermDamageEffect
extends SpellOnHitEffect

## Adds each [StackTerm]'s value to [member CastSpell.damage] IN PLACE at a
## landing: `Σ maxf(0, term.extra(read, host))`, read against THIS cast's world
## ([member PropagationContext.world]) with the cast's read node and the landed
## node — the very call a status rider makes at land, so a damage term and a
## stack term sharing one SubResource agree on a shadow resolve. Emits nothing:
## author it BEFORE [DamageEffect], and the damage effect emits the boosted
## number, which the next hop's mint inherits (it compounds up a walk).

## The terms whose values add to the damage. Share them with the intake row's
## [member AspectIntake.stack_terms] when the spell strips by the same amount.
@export var stack_terms: Array[StackTerm] = []


func _apply_spell(_lctx: LandingContext) -> void:
	pass
