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


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	# The gate takes the world rather than the resolved target slice: it reads
	# the slice of each blade CONTACT's node (`_event.target`), which is not
	# necessarily this hit's own target — a pop is decided against the node the
	# vertex swept into.
	if not _gate.admit(_event, world):
		# A refusal is either "target already dead / vertex already popped" —
		# nothing to say, #502's "no dud for melee" — or THIS contact popping a
		# spike, which is a cue. Only the gate can tell the two apart, so it
		# reports the pop it just made and the hit carries it; see
		# [member HitInstance.popped_vertex] for why it is recorded here rather
		# than announced inside the gate (#536).
		var pop := _gate.last_pop()
		if pop != null:
			popped_vertex = pop.defender
		return
	super.land_on(node, world)
