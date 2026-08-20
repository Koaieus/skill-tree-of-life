class_name BladeDamageInstance
extends DamageInstance

## Melee's land-time gate (#502). [method MeleeAttackPlan.resolve] stays pure
## and up-front — it still emits one of these per non-edge [BladeHitEvent],
## whether or not the swing will actually land it. The live re-check
## (is_allocated() / owned_by / spike-pop, all against the REAL world) happens
## here, in [method land_on], which [OutcomeApplier] calls once per hit in
## [member HitInstance.arrival_time] order — by then any earlier hit in the
## SAME swing has already cascaded (force-dealloc, etc.), so [member _gate]
## sees live state, not the pre-swing snapshot [BladePopResolver.resolve]
## computed for the AI/preview estimate. See docs/domain/attack-timeline.md.

var _event: BladeHitEvent
var _gate: BladePopResolver.LiveGate


func _init(event: BladeHitEvent, gate: BladePopResolver.LiveGate) -> void:
	super._init()
	_event = event
	_gate = gate


func land_on(node: SkillNode) -> void:
	if not _gate.admit(_event):
		return  # target already dead, or this vertex was already popped — no dud
	super.land_on(node)
