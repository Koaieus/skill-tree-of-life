extends GutTest

## OutcomeApplier lands hits in arrival_time order, not append order
## (docs/domain/attack-timeline.md "Ordering and arrival_time") — the half
## of #499's fix that actually changes application order; the ranged ramp
## (test_ranged_attack_plan.gd) is what makes that order meaningful.
##
## Pinned as its own file rather than folded into test_ranged_attack_plan.gd:
## the invariant under test — a stable sort under ties — is orthogonal to
## ranged specifically. It's what keeps this branch mergeable independent of
## #501 (magic) and #502 (melee), which are simultaneously starting to stamp
## real arrival_time onto their own hits.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## Records itself into a shared log on land, instead of touching a real
## SkillNode — lets the test observe application ORDER without depending on
## take_damage/mitigation machinery.
class _RecordingHit extends HitInstance:
	var log: Array

	func _init(p_log: Array, p_arrival: float) -> void:
		log = p_log
		arrival_time = p_arrival

	func land_on(_node: NodeCombat, _world: CombatWorld) -> void:
		log.append(self)


func _hit(log: Array, arrival: float) -> _RecordingHit:
	var h := _RecordingHit.new(log, arrival)
	h.target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	autofree(h.target)
	return h


func test_lands_hits_in_arrival_time_order_not_append_order() -> void:
	var log: Array = []
	var late := _hit(log, 0.5)
	var early := _hit(log, 0.1)
	var mid := _hit(log, 0.3)
	var outcome := AttackOutcome.new()
	outcome.hits.append(late)
	outcome.hits.append(early)
	outcome.hits.append(mid)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_eq(log, [early, mid, late])


func test_ties_preserve_original_append_order() -> void:
	# Every melee/magic hit carries arrival_time == 0.0 today (#501/#502 are
	# mid-flight stamping real values on those modes) — an unstable sort here
	# would permute their application order nondeterministically, which is
	# gameplay-observable (node-local armour + synchronous force-dealloc
	# cascades both read at land time). This is the invariant that makes this
	# branch independent of either sibling landing first.
	var log: Array = []
	var hits: Array[HitInstance] = []
	for i in 20:
		hits.append(_hit(log, 0.0))
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_eq(log, hits, "an all-zero-arrival outcome must land in append order")


func test_a_ranged_outcomes_hit_order_survives_the_applier() -> void:
	# The invariant pinned at the ranged-plan level: RangedAttackPlan.resolve()
	# already emits hits in arrival_time order (nearest leaf first), so the
	# applier's sort must be a no-op for a real ranged outcome — proving the
	# ramp and the applier agree on what "arrival order" means.
	var log: Array = []
	var ordered_arrivals := [0.35, 0.45, 0.60, 0.95]
	var hits: Array[HitInstance] = []
	for a in ordered_arrivals:
		hits.append(_hit(log, a))
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_eq(log, hits, "already-ordered ranged hits must not be reshuffled")
