class_name BladeDamageInstance
extends DamageInstance

## Melee's land-time gate (#502). [method MeleeAttackPlan.resolve] stays pure
## and up-front — it still emits one of these per [BladeHitEvent], vertex or
## edge (#785), whether or not the swing will actually land it. The live re-check
## (is_allocated() / owned_by / spike-pop, against the landing world) happens
## here, in [method resolve_gate], asked as this contact's beat opens
## ([method HitGather.stage_one]) — by then every earlier beat of the SAME
## swing has cascaded (force-dealloc, etc.), so [member _gate] sees that state,
## not the pre-swing snapshot [BladePopResolver.resolve] computed for the
## AI/preview estimate; a refused contact sets nothing off. See
## docs/domain/attack-timeline.md.

var _event: BladeHitEvent
var _gate: BladePopResolver.LiveGate
## True once [method resolve_gate] passed the gate — what a status riding this
## hit reads through [method landed] instead of re-asking the gate (#951): a
## second `admit` of the same event can pop the vertex twice.
var admitted: bool = false
var _gate_resolved: bool = false
## The pop an ADMITTED contact made (a one-shot vertex's, or
## [method snap_on_ice]'s), stamped on [member HitInstance.popped_vertex] as
## this contact lands.
var _landed_pop: BladePopResolver.Pop = null


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
	if _landed_pop != null:
		popped_vertex = _landed_pop.defender


## The raw amount, stamped as this contact's beat opens its gather, on the
## gather's world: the minted coefficient (`vertex_damage[i]`) × the speed curve
## at the contact's speed scaled by the sweep factor of the node it lands on,
## read before generation 0 lands any rider. Before armor: the break read
## mitigates it. Stamped before the gate is asked: a refused contact is stamped
## too, and lands nothing.
func stamp_at_gather(world: CombatWorld) -> void:
	var t := 0
	var threshold := 0
	var slice := world.combat_for(target) if world != null and target != null else null
	if slice != null:
		t = slice.terrain_t()
		threshold = slice.terrain_threshold()
	sweep_factor = sweep_factor_of(attacker, t, threshold)
	amount *= contact_multiplier(attacker, _event.speed, t, threshold)


## The speed curve one contact deals at, [param speed] scaled by the sweep
## factor at a node of signed [param t] and threshold [param threshold],
## [param wielder]'s board read (a boardless fixture: m 1, c 0). The one
## formula the gather stamp and [method SkillBlade._speed_multiplier] share.
static func contact_multiplier(wielder: Entity, speed: float, t: int, threshold: int) -> float:
	var board: StatBoard = wielder.stat_board if wielder != null else null
	var m := BladeState.stat_value(board, &"blade_speed_multiplier_max", 1.0)
	var v_half := BladeState.stat_value(board, &"blade_speed_half", 0.0)
	return BladeState.speed_damage_multiplier(
			speed * sweep_factor_of(wielder, t, threshold), m, v_half)


## The sweep factor alone ([method BladeState.temperature_speed_factor] at
## [param wielder]'s `c`): what [method contact_multiplier] scales the speed
## by, and what the stamp records as the floater's cue.
static func sweep_factor_of(wielder: Entity, t: int, threshold: int) -> float:
	var board: StatBoard = wielder.stat_board if wielder != null else null
	var c := clampf(BladeState.stat_value(board, &"blade_temperature_speed", 0.0), 0.0, 0.95)
	return BladeState.temperature_speed_factor(t, threshold, c)


## The contacting vertex's copied terrain, a second store the gather sets off
## at this contact's node: every vertex contact answers one, primed or inert.
func go_off_source() -> GoOffSource:
	var state := _gate.state() if _gate != null else null
	if state == null or _event == null or _event.particle_idx < 0:
		return null
	var idx := _event.particle_idx
	return GoOffSource.new(state, idx, state.copy_read(idx),
			func(e: Element, n: int) -> void: state.spend_copy(idx, e, n))


## The contacting vertex's weight: its build-time mass, [method weight_of] its
## source radius × every [member BunkerAddon.blade_mass] its source carries.
## Never the sim's `inv_masses` (0 for the pivot and a corpse) and nothing
## per-contact. -1 for an edge contact or a contact with no blade.
func touch_weight() -> float:
	var state := _gate.state() if _gate != null else null
	if state == null or _event == null or _event.particle_idx < 0 \
			or _event.particle_idx >= state.radii.size():
		return -1.0
	var idx := _event.particle_idx
	var w := weight_of(state.radii[idx])
	var source: SkillNode = state.vertex_node[idx] if idx < state.vertex_node.size() else null
	if source != null:
		for addon in source.get_addons():
			if addon is BunkerAddon and (addon as BunkerAddon).blade_mass > 0.0:
				w *= (addon as BunkerAddon).blade_mass
	return w


## A disc's weight: its area, `(radius / MASS_REF_RADIUS)²` — the vertex's and
## the node's one formula, so equal radii tie exactly.
static func weight_of(radius: float) -> float:
	var r := radius / BladeState.MASS_REF_RADIUS
	return r * r


## Pop this contact's vertex on ice: the node it landed on is still Frozen
## after the contact's own terrain riders ([method FrozenAdmits.read_in] asks,
## once per generation). The vertex dies now (a later contact is refused);
## the hit carries the pop from its own landing ([method land_on]), so the
## break's extra landings, cloned from this head in stage one, carry none. A
## refused contact, the pivot, an edge or a dead vertex pops nothing.
func snap_on_ice() -> void:
	if not admitted or _gate == null:
		return
	var pop := _gate.snap(_event, target)
	if pop != null:
		_landed_pop = pop


## The gate, decided once — by the gather as this contact's beat opens, by a
## status rider landing ahead of it or by its [method land_on], whichever asks
## first (the gather, on a fresh resolve) — so `admit`'s
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
		# Stamped as the contact lands ([method land_on]), so a go-off copy or
		# a break's extra landing cloned from this head in stage one carries none.
		_landed_pop = _gate.last_pop()
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
