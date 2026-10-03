@tool
@abstract
class_name SpellOnHitEffect
extends OnHitEffect

## An [OnHitEffect] that reads SPELL context — the propagated
## [member CastSpell.damage], the cast's world queries — and so only means
## something on a spell's landing (ADR 0044). [method apply] narrows the
## mode-agnostic [HitLanding] to the [LandingContext] the spell resolver
## builds and hands it to [method _apply_spell]; on any other landing it does
## nothing. An effect that needs only the landing's shared facts extends
## [OnHitEffect] directly instead, and works in every mode ([ApplyStatusEffect]).


func apply(landing: HitLanding) -> void:
	var lctx := landing as LandingContext
	if lctx == null:
		return
	_apply_spell(lctx)


## [param lctx]'s [code]payload[/code] is the landing's resolved, mutable
## [CastSpell]; [code]lctx.cast.outcome[/code] the cast's ledger (#356).
@abstract func _apply_spell(lctx: LandingContext) -> void
