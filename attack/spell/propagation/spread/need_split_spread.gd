@tool
class_name NeedSplitSpread
extends PropagationSpread

## Splits a cleanse's leftover dose over the already-filtered children, BY
## NEED: the whole-number leftover ([code]floor(payload.damage)[/code], the
## dose the landing's [CureEffect] wrote back in place) is apportioned by
## [method Apportion.largest_remainder], weighted by [method Cure.need_of],
## and each pick carries [code]share = alloc / leftover[/code] — so the shares × leftover
## sum to the leftover exactly. Ties in the remainder go to the earlier
## eligible node (deterministic across peers); picks come out in eligible
## order. A zero-need child, or one whose allocation rounds to 0, gets no
## pick; a leftover under one whole dose gives none at all.
##
## Pair with [code]MultiplyProgression[/code] factor 1.0 and a
## [SumDamageReducer], which conserves the dose where branches meet; a
## [MaxDamageReducer] would silently lose dose.

## The SAME [Cure] the spell's [CureEffect] holds, by reference — its price
## table is what "need" means.
@export var cure: Cure = null

const _EPS := 1e-6


func select(eligible: Array[SkillNode], lctx: LandingContext) -> Array[PropagationPick]:
	var out: Array[PropagationPick] = []
	if cure == null or lctx.payload == null:
		return out
	var leftover := int(floorf(lctx.payload.damage + _EPS))
	if leftover <= 0:
		return out
	var needs: Array[float] = []
	for nb in eligible:
		needs.append(cure.need_of(nb, lctx))
	var alloc := Apportion.largest_remainder(leftover, needs)
	for i in eligible.size():
		if alloc[i] > 0:
			out.append(PropagationPick.to(eligible[i], float(alloc[i]) / float(leftover)))
	return out


func get_description() -> String:
	return "Leftover dose splits by need."
