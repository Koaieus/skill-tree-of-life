class_name OutcomeApplier

## The one place an [AttackOutcome] is applied to the world — the double-
## dispatch counterpart to [method HitInstance.land_on] (#381). A static
## utility rather than a Node/system: [method BattleSystem._apply_outcome]
## is its only caller today (#474 made VFX a pure observer, so the
## original two-caller design this issue started from no longer applies —
## see the plan/issue history), but it's named and isolated deliberately as
## the deterministic "apply this outcome" boundary #458's command-replay
## model will want.


## Land every hit in [member HitInstance.arrival_time] order, not append
## order (docs/domain/attack-timeline.md "Ordering and arrival_time") — this
## is the half that actually fixes allocation order leaking into combat
## outcome; the per-mode ramps (ranged's rank-authored schedule, magic's
## propagation beat, melee's `BladeHitEvent.t`) are what make the order
## meaningful. [method RevealRecorder.push_cause] still stamps each hit's own
## `arrival_time` onto whatever it records, and [PresentationPlayer] is what
## makes the view catch up later.
static func apply(outcome: AttackOutcome) -> void:
	for hit in _in_arrival_order(outcome.hits):
		if hit.target != null:
			RevealRecorder.push_cause(hit.arrival_time)
			hit.land_on(hit.target)
			RevealRecorder.pop_cause()


## Decorate-sort-undecorate on `(arrival_time, original_index)`.
## [method Array.sort_custom] is not documented stable in Godot 4.x, and
## every melee/magic hit still carries `arrival_time == 0.0` today (#501,
## #502 are mid-flight stamping real values on those modes) — an unstable
## sort would permute their application order nondeterministically, which is
## gameplay-observable here (node-local armour + synchronous force-dealloc
## cascades both read at land time). Sorting on the original index as a
## tiebreak makes this a provable no-op for any outcome whose hits all tie.
##
## [member SkillNode.stable_id] is NOT the tiebreak here — it's the ranged
## ramp's OWN rank tiebreak (see [method RangedAttackPlan.get_firing_schedule]).
## Applied globally it would reorder magic hits out of wave order.
static func _in_arrival_order(hits: Array[HitInstance]) -> Array[HitInstance]:
	var decorated: Array = []
	for i in hits.size():
		decorated.append([hits[i].arrival_time, i, hits[i]])
	decorated.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(a[0], b[0]):
			return a[0] < b[0]
		return a[1] < b[1])
	var ordered: Array[HitInstance] = []
	for entry in decorated:
		ordered.append(entry[2])
	return ordered
