@tool
class_name TierLadder
extends Resource

## The single shared cost/value ladder for the procgen v4 draw model (#321).
## One law for the whole game: `value = 2 * cost - 1`, so `cost[t] = 2^(t-1)`
## and `V[t] = 2^t - 1`. Retuning the game's cost curve is now a one-file edit
## (the original ask of #321); per-pool authoring only carries `unit_value` and
## optional `value_overrides` — never costs or the value curve.
##
## T1..T4 only. `tier` is a global cost band, stored as int — not an enum, since
## the draw does arithmetic on it (`cost(T)`, `V[T]`, `tier ≤ peak-1`, sorting)
## and #319's lesson is "don't add an enum encoding a fact another field already
## carries." See docs/domain/procgen-v4.md (D1, D2).
##
## Tags are auto-stamped from tier at flatten time (D5) so the existing radial
## band profile (`rbp_main`) keeps gating content that can actually be rolled:
##   tier_1..tier_4   always
##   T1, T2 -> common · T3 -> rare · T4 -> mythic

const COSTS := [1, 2, 4, 8]
const MIN_TIER := 1
const MAX_TIER := 4


static func cost(tier: int) -> int:
	return COSTS[clampi(tier - MIN_TIER, 0, COSTS.size() - 1)]


static func value(tier: int) -> float:
	return 2.0 * cost(tier) - 1.0


static func tier_tag(tier: int) -> StringName:
	return StringName("tier_%d" % clampi(tier, MIN_TIER, MAX_TIER))


## Rarity tag stamped from tier (D5): T1/T2 common, T3 rare, T4 mythic.
static func rarity_tag(tier: int) -> StringName:
	match clampi(tier, MIN_TIER, MAX_TIER):
		1, 2: return &"common"
		3: return &"rare"
		4: return &"mythic"
		_: return &"common"


## All auto-stamped tags for a tier (tier_N + rarity). Appended to a pool's own
## `tags` at flatten time so [WeightProfile]s key off stable handles.
static func auto_tags(tier: int) -> Array[StringName]:
	return [tier_tag(tier), rarity_tag(tier)]
