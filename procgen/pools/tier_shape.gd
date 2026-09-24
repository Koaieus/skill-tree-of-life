@tool
class_name TierShape
extends Resource

## The one law for a [StatPool]'s per-tier weight: `w(t) = t^power × ratio^(t-1)`,
## where `t` is the ABSOLUTE tier (1..[constant TierLadder.MAX_TIER], the same
## index as [method TierLadder.cost]) — never the rung counted from a pool's
## `min_tier`. Only relative weights within one pool matter; the draw multiplies
## them by the pool's `pool_weight`. Nothing else computes a tier weight.
##
## The default (`power 0, ratio 2`) is `1, 2, 4, 8` — weight proportional to
## cost. `ratio = 2^k` at `power 0` reproduces the retired `cost^k` law exactly,
## since `cost(t)^k = (2^k)^(t-1)`. `power 1, ratio 1` is linear, `ratio 1` alone
## is flat, and `power > 0` with `ratio < 1` makes a hump. Formulaic by design:
## no per-tier arrays, so a fifth tier needs no re-authoring.

## Polynomial lean toward high tiers: `t^power`. `0` leaves it out.
@export var power: float = 0.0:
	set(v):
		power = v
		emit_changed()

## Geometric step per tier: `ratio^(t-1)`. `2` tracks the cost ladder, `1` is
## flat, below `1` suppresses high tiers.
@export var ratio: float = 2.0:
	set(v):
		ratio = v
		emit_changed()


func weight(tier: int) -> float:
	return pow(float(tier), power) * pow(ratio, tier - 1)
