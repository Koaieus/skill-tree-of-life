class_name BladeDamageInstance
extends DamageInstance

## Melee's land-time gate (#502). [method MeleeAttackPlan.resolve] stays pure
## and up-front — it still emits one of these per [BladeHitEvent], vertex or
## edge (#785), whether or not the swing will actually land it. The live re-check
## (is_allocated() / owned_by / spike-pop, all against the REAL world) happens
## here, in [method land_on], which [OutcomeApplier] calls once per hit in
## [member HitInstance.arrival_time] order — by then any earlier hit in the
## SAME swing has already cascaded (force-dealloc, etc.), so [member _gate]
## sees live state, not the pre-swing snapshot [BladePopResolver.resolve]
## computed for the AI/preview estimate. See docs/domain/attack-timeline.md.

var _event: BladeHitEvent
var _gate: BladePopResolver.LiveGate
## True once [method land_on] passed the gate — what a status riding this
## hit reads through [method landed] instead of re-asking the gate (#951): a
## second `admit` of the same event can pop the vertex twice.
var admitted: bool = false
var _gate_resolved: bool = false


func _init(event: BladeHitEvent, gate: BladePopResolver.LiveGate) -> void:
	super._init()
	_event = event
	_gate = gate


## A go-off copy lands as a plain [DamageInstance], as a record rebuilds one:
## it never re-runs this contact's gate on the node it reaches.
func blank_copy() -> HitInstance:
	return DamageInstance.new()


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	resolve_gate(world)
	if not admitted:
		return
	# `amount` is already the raw amount: [method stamp_at_gather] multiplied
	# the curve in once, on the authority's gather. A peer's rebuilt plain
	# [DamageInstance] carries the post-mitigation number instead (ADR 0002).
	super.land_on(node, world)


## The raw amount, stamped as this contact's beat opens its gather, on the
## gather's world: the minted coefficient (`vertex_damage[i]`) × the speed curve
## at the contact's speed scaled by the sweep factor of the node it lands on,
## read before generation 0 lands any rider. Before armor: the break read
## mitigates it. A refused contact is stamped too, and lands nothing.
func stamp_at_gather(world: CombatWorld) -> void:
	var t := 0
	var threshold := 0
	var slice := world.combat_for(target) if world != null and target != null else null
	if slice != null:
		t = slice.terrain_t()
		threshold = slice.terrain_threshold()
	amount *= contact_multiplier(attacker, _event.speed, t, threshold)


## The speed curve one contact deals at, [param speed] scaled by the sweep
## factor at a node of signed [param t] and threshold [param threshold],
## [param wielder]'s board read (a boardless fixture: m 1, c 0). The one
## formula the gather stamp and [method SkillBlade._speed_multiplier] share.
static func contact_multiplier(wielder: Entity, speed: float, t: int, threshold: int) -> float:
	var board: StatBoard = wielder.stat_board if wielder != null else null
	var m := BladeState.stat_value(board, &"blade_speed_multiplier_max", 1.0)
	var v_half := BladeState.stat_value(board, &"blade_speed_half", 0.0)
	var c := clampf(BladeState.stat_value(board, &"blade_temperature_speed", 0.0), 0.0, 0.95)
	var factor := BladeState.temperature_speed_factor(t, threshold, c)
	return BladeState.speed_damage_multiplier(speed * factor, m, v_half)


## The contacting vertex's copied terrain, a second store the gather sets off
## at this contact's node: every vertex contact answers one, primed or inert.
func go_off_source() -> GoOffSource:
	var state := _gate.state() if _gate != null else null
	if state == null or _event == null or _event.particle_idx < 0:
		return null
	var idx := _event.particle_idx
	return GoOffSource.new(state, idx, state.copy_read(idx),
			func(e: Element, n: int) -> void: state.spend_copy(idx, e, n))


## The gate, decided once — by this contact's [method land_on] or by a
## status rider landing ahead of it, whichever asks first — so `admit`'s
## "exactly once per event" holds and a spike pops once. The gate takes the
## world rather than the resolved target slice: it reads the slice of each
## blade CONTACT's node (`_event.target`) — a pop is decided against the node
## the vertex swept into.
func resolve_gate(world: CombatWorld) -> void:
	if _gate_resolved or _gate == null:
		return
	_gate_resolved = true
	if _gate.admit(_event, world):
		admitted = true
		# An admitted contact may still pop its vertex (a one-shot vertex lands,
		# then dies): the hit carries that pop as a refused spike contact does.
		var popped := _gate.last_pop()
		if popped != null:
			popped_vertex = popped.defender
		return
	# A refusal is either "target already dead / vertex already popped" —
	# nothing to say, #502's "no dud for melee" — or THIS contact popping a
	# spike, which is a cue. Only the gate can tell the two apart, so it
	# reports the pop it just made and the hit carries it; see
	# [member HitInstance.popped_vertex] for why it is recorded here rather
	# than announced inside the gate (#536).
	var pop := _gate.last_pop()
	if pop != null:
		popped_vertex = pop.defender


## Melee's refusal is not a dud (#502 — [member HitInstance.gated] stays
## false), so the paired gate is the admission itself: a refused contact
## lands its riders as power-0 duds ([member HitInstance.paired]).
func landed() -> bool:
	return admitted
