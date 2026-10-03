@tool
@abstract
class_name SpellOnHitEffect
extends OnHitEffect

## An [OnHitEffect] that reads SPELL context — the propagated
## [member CastSpell.damage], the cast's world queries — and so only means
## something on a spell's landing (ADR 0044). [method apply] narrows the
## mode-agnostic [HitLanding] to the [LandingContext] the spell resolver
## builds and hands it to [method _apply_spell]; on any other landing it does
## nothing but report it once — a spell effect on an arrow's or a blade's
## [code]on_hit_effects[/code] is an authoring error. An effect that needs only the landing's shared facts extends
## [OnHitEffect] directly instead, and works in every mode ([ApplyStatusEffect]).


## Once per effect instance: an authoring error is worth one line, not one
## per landing.
var _warned_not_spell: bool = false


func apply(landing: HitLanding) -> void:
	var lctx := landing as LandingContext
	if lctx == null:
		if not _warned_not_spell:
			_warned_not_spell = true
			push_error("%s needs a spell landing (LandingContext); it does nothing on this one"
					% get_script().get_global_name())
		return
	_apply_spell(lctx)


## [param lctx]'s [code]payload[/code] is the landing's resolved, mutable
## [CastSpell]; [code]lctx.cast.outcome[/code] the cast's ledger (#356).
@abstract func _apply_spell(lctx: LandingContext) -> void
