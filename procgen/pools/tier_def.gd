@tool
class_name TierDef
extends Resource

## One tier in a [TierPool]. Carries only the per-tier triple
## (value_range, cost, weight) plus an optional tier label and extra tags;
## stat_id / operation / role / shared tags live one level up on [TierPool].
##
## A pool's tiers are typically authored T1..T5 ascending in both cost and
## magnitude — but nothing enforces this. The roll loop only cares about
## cost ≤ budget and weight.

@export var tier: int = 1
## Inclusive magnitude range sampled at roll time. Both ends equal = fixed.
@export var value_range: Vector2 = Vector2(1.0, 1.0)
## Budget cost. Floor of 1 keeps per-node draw count bounded.
@export var cost: int = 1
## Base sampling weight before [WeightProfile] modulation.
@export var weight: float = 1.0
## Tier-specific extra tags appended to the parent pool's `tags` at flatten.
## Use for one-off flavour ("exotic", "godly") that doesn't belong on every
## tier of the pool.
@export var extra_tags: Array[StringName] = []
