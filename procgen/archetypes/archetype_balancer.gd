@tool
class_name ArchetypeBalancer
extends Resource

## Pittman-style dynamic-Markov rebalance. Instead of letting RNG streaks
## tilt archetype distribution, the picker walks a running count of
## already-assigned archetypes and skews each pick toward whichever
## archetype is currently UNDER its target share.
##
## Formula (per archetype t):
##   effective_weight(t) = base_weight(t)
##                       × (target_ratio(t) − current_ratio(t) + ε)
##
## ε keeps multipliers strictly positive (no archetype locked out). Small ε
## (e.g. 0.01) = strict ratios; larger (e.g. 0.5) = light bias.
##
## In v2's cluster-plan model, target ratios are already largely honoured by
## `target_count` sampling. ArchetypeBalancer is the dial for fine-tuning
## the cluster_jitter reroll + fallback paths so streaks of "kept landing
## on red" get gently corrected. **Off by default.**

@export var enabled: bool = false
@export var strength_epsilon: float = 0.1


## Returns the index into `archetypes` of the picked archetype, given the
## running per-archetype assignment counts. Uses each archetype's
## `target_ratio` as its base weight.
func pick(
		archetypes: Array[ArchetypePolicy],
		counts: PackedInt32Array,
		total_assigned: int,
		rng: RandomNumberGenerator,
) -> int:
	if archetypes.is_empty():
		return -1
	var total_target := 0.0
	for a in archetypes:
		if a != null:
			total_target += maxf(0.0, a.target_ratio)
	if total_target <= 0.0:
		return rng.randi() % archetypes.size()
	var effective: Array[float] = []
	var sum := 0.0
	for i in archetypes.size():
		var a := archetypes[i]
		if a == null:
			effective.append(0.0)
			continue
		var target_ratio := maxf(0.0, a.target_ratio) / total_target
		var current_ratio := 0.0 if total_assigned <= 0 else float(counts[i]) / float(total_assigned)
		var w := maxf(0.0, target_ratio - current_ratio + strength_epsilon)
		effective.append(w)
		sum += w
	if sum <= 0.0:
		return rng.randi() % archetypes.size()
	var r := rng.randf() * sum
	for i in effective.size():
		r -= effective[i]
		if r <= 0.0:
			return i
	return archetypes.size() - 1
