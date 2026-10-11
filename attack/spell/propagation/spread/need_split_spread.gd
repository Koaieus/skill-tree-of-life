@tool
class_name NeedSplitSpread
extends PropagationSpread

## Splits a cleanse's leftover dose over the already-filtered children, BY
## NEED: the whole-number leftover ([code]floor(payload.damage)[/code], the
## dose the landing's [CureEffect] wrote back in place) is apportioned by
## largest remainder, weighted by [method Cure.need_of], and each pick
## carries [code]share = alloc / leftover[/code] — so the shares × leftover
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
	var total := 0.0
	for nb in eligible:
		var need := maxf(cure.need_of(nb, lctx), 0.0)
		needs.append(need)
		total += need
	if total <= 0.0:
		return out
	var alloc: Array[int] = []
	var fracs: Array[float] = []
	var given := 0
	for need in needs:
		var quota := leftover * need / total
		var whole := int(floorf(quota + _EPS))
		alloc.append(whole)
		fracs.append(quota - whole)
		given += whole
	# Hand the remaining units to the largest remainders; a stable sort keeps
	# the earlier eligible node first on a tie. Zero-need nodes never qualify.
	var order: Array = range(needs.size()).filter(func(i: int) -> bool: return needs[i] > 0.0)
	order.sort_custom(func(a: int, b: int) -> bool:
		return fracs[a] > fracs[b] + _EPS or (absf(fracs[a] - fracs[b]) <= _EPS and a < b))
	for k in mini(leftover - given, order.size()):
		alloc[order[k]] += 1
	for i in eligible.size():
		if alloc[i] > 0:
			out.append(PropagationPick.to(eligible[i], float(alloc[i]) / float(leftover)))
	return out


func get_description() -> String:
	return "Leftover dose splits by need."
