class_name SwingResolve
extends RefCounted
## One resumable run of the swing resolve — the loop [method
## MeleeAttackPlan._resolve_swing] used to hold inline, hoisted into an object
## so it can be driven either straight through (the authoritative path: one
## optimistic bake of the whole remaining swing per severance) or a slice at a
## time across frames (#821's aim-time preview).
##
## [b]There is still exactly ONE chunked loop.[/b] Slicing is not a second code
## path — [method advance] takes a step budget, and an unbounded budget (<= 0)
## reproduces the old whole-remainder bake exactly. Everything the severance
## head-replay already did to stitch a chunk boundary is what a slice boundary
## rides on: one [BladeSwingClock] instance carried across, one
## [BladeObstacleField] carried across, and [member BladeState.speed_history]
## accumulated out of each bake's chunk-local array.
##
## [b]Those three histories are chunk-local BY DESIGN[/b] — `clock.history`,
## `obstacles.history` and `state.speed_history` are rebuilt per bake, so a
## sliced caller has to stitch them rather than assume they accumulate. Getting
## it wrong is not a visible glitch: a fresh clock mid-swing un-banks a
## Fortification wall's drag and silently stops it sheltering what is behind it
## (`test_blade_chunked_parity.gd:200-203`). That an arbitrary boundary is
## bit-identical to no boundary at all is pinned by
## `test_a_dragged_swing_is_bit_identical_across_a_chunk_boundary`.
##
## A slice boundary differs from a severance boundary in exactly one way: there
## is nothing to rewind to. The bake ran to the boundary and stopped, so the
## state, the clock and the field are already where the next bake continues
## from — nothing is restored, which is the shape that parity test runs.
## The bundle, LIVE. `outcome`, `pops`, `live_gate`, `clock` and `obstacles`
## are set before the first step; `trajectory`, `events` and `hits` the
## moment the guards pass — and they are the very arrays the run appends to,
## so a PARTIAL run is readable and grows in place. See
## [method MeleeAttackPlan.prediction_partial].
var result: SwingResult = SwingResult.new()

var _ctx: SwingContext = null
var _world: CombatWorld = null
var _outcome: AttackOutcome = null
var _state: BladeState = null
var _drivers: Array[BladeDriver] = []
var _clock: BladeSwingClock = null
var _obstacles: BladeObstacleField = null
var _gate: BladePopResolver.LiveGate = null
var _sweep: BladeHitScan.Sweep = null
var _trajectory: BladeTrajectory = null
var _speed_history: Array[PackedFloat32Array] = []
var _events: Array[BladeHitEvent] = []
var _hits: Array[DamageInstance] = []
var _rng: RandomNumberGenerator = null
var _dt: float = BladeSim.DEFAULT_DT
var _total_steps: int = 0
## The GLOBAL sample index the next bake starts from. Moves to a severance
## sample (rewound) or to the end of the last bake (a slice boundary).
var _chunk_start: int = 0
var _done: bool = false
## #796: the peer draw-only resim's fidelity knob. Both default to the
## authoritative/aim-time values (`BladeSim.DEFAULT_SUBSTEPS`, scaling on) —
## only [method MeleeAttackPlan.begin_replay_resolve] ever passes anything
## else, and it does so because ADR 0002 makes that call's whole run
## draw-only: no hit, pop or damage number this class produces is kept, so
## degrading its solve buys nothing to lose.
var _substeps: int = BladeSim.DEFAULT_SUBSTEPS
var _enable_length_scaling: bool = true


func _init(ctx: SwingContext) -> void:
	_ctx = ctx
	_world = ctx.world
	_dt = ctx.dt
	_substeps = ctx.substeps
	_enable_length_scaling = ctx.enable_length_scaling
	var resolve_seed := ctx.resolve_seed
	var outcome := AttackOutcome.new()
	_outcome = outcome
	result.outcome = outcome
	outcome.cadence = ScheduleEntry.Cadence.SWING
	# Spelled through a local rather than `ctx.resolve_seed` because
	# `test_attack_determinism.gd` pins this line, and the next crit-stream
	# one, as SOURCE TEXT — a refactor that quietly stopped drawing off the
	# stamped seed is exactly what that guard exists to catch.
	outcome.resolve_seed = resolve_seed
	# A null state is the invalid-plan shape — see [SwingContext].
	_state = ctx.state
	if _state == null:
		_done = true
		return
	_drivers = ctx.drivers
	# The defender field (#811) carries both kinds; the clock is its
	# accumulator half. Fortification drag (#780) bogs the swing's own clock
	# down cumulatively from the moment the blade first touches a wall, and a
	# bunker's grip stall (#781) is expressed on the same clock — so a swing
	# with any defender in reach gets one, and a swing with none gets neither.
	# ONE clock for the whole swing, carried across every chunk — see
	# BladeSwingClock.Bank. An untouched clock is bit-inert
	# (test_blade_swing_drag pins it) and the field already forces the GDScript
	# backend, so a plates-only swing pays nothing extra for having one.
	_obstacles = _state.obstacles
	if _obstacles != null:
		_clock = BladeSwingClock.new(ctx.swing_duration)
	var space_state := ctx.space_state
	var exclude := ctx.excludes
	var graph := ctx.graph
	# #170/#502/#536: ONE pop gate for the whole swing, re-evaluated per event at
	# land time, so it sees this swing's own cascades. Since #801 it also sees
	# them EARLY ENOUGH TO MATTER: a death lands before the samples after it are
	# simulated, so the solver can react to it.
	_gate = BladePopResolver.LiveGate.new(_state, ctx.attacker)
	result.live_gate = _gate
	result.pops = _gate.result
	result.clock = _clock
	result.obstacles = _obstacles
	# #530: each batch stable-sorts on SkillNode.stable_id, so the hit SET a pop
	# cascade sees never depends on physics broadphase order.
	if space_state != null:
		_sweep = BladeHitScan.Sweep.new(_state, space_state, graph, 0xFFFFFFFF, exclude)

	_total_steps = int(ceil(ctx.swing_duration / _dt))
	_trajectory = BladeTrajectory.new()
	_trajectory.sample_dt = _dt
	_trajectory.samples = [_state.positions.duplicate()]
	var zero_speeds := PackedFloat32Array()
	zero_speeds.resize(_state.positions.size())
	_speed_history = [zero_speeds]
	# ONE crit stream for the whole swing, handed to every batch's `decide_all`
	# in turn (#507). Batches run in `t` order and `OutcomeSchedule._sorted` is
	# stable on insertion, so the stream is consumed in exactly the order a
	# single `decide_all` over the finished hit list would have consumed it —
	# which is why an unsevered swing rolls the identical crits it did before
	# the interleave. #186's per-round salt is gone with the rounds.
	_rng = CritRoll.stream_for(resolve_seed)
	# Published now, not at the end: these three ARE the partial picture.
	result.trajectory = _trajectory
	result.events = _events
	result.hits = _hits


func is_done() -> bool:
	return _done


## How far the trajectory has been resolved, 0..1. For a surface that wants
## to say "still computing" — nothing does yet (#821 raised it as a design
## question rather than inventing an answer).
func progress() -> float:
	if _total_steps <= 0:
		return 1.0
	return clampf(float(_chunk_start) / float(_total_steps), 0.0, 1.0)


## The trajectory-TIME length this run will finish at, known from the swing
## duration up front — unlike [method BladeTrajectory.duration], which
## derives purely from `samples.size()` and so underreports while a slice
## run is still mid-flight. #796: a mirror's [method MeleePreview.launch]
## needs the real span to size its playback tween BEFORE the resim driving
## it has finished.
func total_duration() -> float:
	return float(_total_steps) * _dt


## Resolve at most [param max_steps] more trajectory samples; true when the
## whole swing is resolved. A budget of 0 or less means "the rest of it",
## which is the authoritative path's single call.
func advance(max_steps: int) -> bool:
	if _done:
		return true
	var budget := max_steps
	while _chunk_start < _total_steps:
		var remaining := _total_steps - _chunk_start
		# OPTIMISTIC BAKE: the whole remaining swing in one call, assuming
		# nothing dies. Because a bake is a pure function of the state, walking
		# it sample by sample and re-baking from the first death produces the
		# bit-identical trajectory a true per-sample interleave would (#801) —
		# at one solver call per SEVERANCE instead of one per sample. A budget
		# caps the same call short; the boundary it creates is stitched exactly
		# like a severance boundary, minus the rewind.
		var count := remaining if budget <= 0 else mini(budget, remaining)
		var chunk := BladeSim.simulate_range(
				_state, _drivers, _chunk_start, count, _dt,
				BladeSim.DEFAULT_ITERATIONS, 0.0, _substeps,
				_enable_length_scaling, _clock)
		if chunk == null:
			# The native solver declined this bake and has already
			# push_error'd why (#847 — there is no GDScript fallback to
			# fall back ON). Stop with the trajectory resolved so far
			# rather than crashing on `chunk.samples` one line down: the
			# error above is the diagnosis, and a nil-access here would
			# bury it.
			_done = true
			return true
		var chunk_speeds := _state.speed_history
		var severed_at := -1
		for j in range(1, chunk.samples.size()):
			var step := _chunk_start + j
			var pose: PackedVector2Array = chunk.samples[j]
			var speeds: PackedFloat32Array = chunk_speeds[j]
			_trajectory.samples.append(pose)
			_speed_history.append(speeds)
			var pops_before := _gate.result.pops.size()
			var landed := false
			if _sweep != null:
				var batch := _sweep.scan_sample(float(step) * _dt, pose, speeds)
				if not batch.is_empty():
					landed = true
					_events.append_array(batch)
					_land_batch(_outcome, batch, _state, _gate, _world, _rng, _hits)
			# #867: a landing's forced-dealloc cascade can disown a DEFENDER —
			# a wall or plate this swing itself destroyed, directly or by
			# islanding it. That severs exactly like a bunker break does: the
			# rest of this bake was computed with the zone still in the field,
			# so it is thrown away and re-baked without it, and the zone stops
			# mattering from this sample on rather than at the next swing.
			# Asked only on a sample that landed something, because a cascade
			# has no other door into a swing; then it is O(defenders in reach),
			# never the O(map) walk #811 deleted.
			var disowned := landed and _obstacles != null \
					and _obstacles.has_disowned_defender(_world)
			# A bunker break (#781) is decided INSIDE the bake, by the field, at
			# the substep the strain crossed the threshold — so it is checked
			# per sample whether or not anything was hit, and severs exactly
			# like a pop: stop, rewind, apply, re-bake.
			var broke := _obstacles != null and _obstacles.has_break_at(step)
			if _gate.result.pops.size() != pops_before or broke or disowned:
				severed_at = step
				break
		if severed_at < 0:
			# A PLAIN BOUNDARY. The bake ran to `_chunk_start + count` and the
			# state, the clock and the field are all standing there — nothing to
			# rewind, nothing to restore. When `count` was the whole remainder
			# this ends the loop, which is the pre-#821 shape verbatim.
			_chunk_start += count
		else:
			# REWIND TO THE DEATH. The bake above ran past it, so `state` is at the
			# end of the swing, not at `severed_at`. The bake recorded the exact
			# state at every sample — `prev_samples` alongside `samples`, and the
			# clock its own bank (#803) — so landing on the severance sample is a
			# read, not a re-run. (`_step` rewrites `prev_positions` once per
			# SUBSTEP, so it is a mid-sample pose that `samples` alone could never
			# recover; #801 re-baked the head of the chunk to get it before both
			# backends emitted it.) Duplicated because `_step` writes through the
			# reference, and the trajectory keeps these same arrays.
			#
			# The three histories are indexed CHUNK-LOCAL, so the index is
			# relative to this bake's own start — never the global step.
			var local := severed_at - _chunk_start
			_state.positions = chunk.samples[local].duplicate()
			_state.prev_positions = chunk.prev_samples[local].duplicate()
			if _clock != null:
				_clock.restore(_clock.history[local])
			if _obstacles != null:
				_obstacles.restore(_obstacles.history[local])
			# THE WHOLE OF A SEVERANCE: a corpse frozen where it died, its
			# constraints and its driver gone, and drag written onto whatever it was
			# holding on. Nothing else — everything downstream then coasts by plain
			# Verlet, because that is what Verlet does to a particle nothing is
			# pulling on.
			# The bank restored just above IS the one the break was armed in — the
			# field banks once per sample, after that sample's substeps — so the
			# break is consumed HERE, off the rewound field, with nothing re-run.
			if _obstacles != null:
				var brk := _obstacles.consume_break()
				if brk != null:
					_gate._sever_edge(brk.edge_idx, float(severed_at) * _dt, brk.defender, 0.0)
				# #867: and retire whatever the cascade disowned — AFTER the
				# restore above, which puts back the pre-death strain and any
				# armed break, and after `consume_break`, because a break armed
				# by THIS sample's substeps was armed by a plate that was still
				# alive for them. Unconditional rather than gated on
				# `disowned`: a pop or a break severance can disown a defender
				# too, the call is idempotent, and the walk is O(zones).
				_obstacles.retire_disowned_defenders(_world)
			for pop in _gate.result.pops:
				if pop.particle_idx >= 0:
					_state.remove_vertex(pop.particle_idx)
			for severance in _gate.result.severances:
				for v in severance.vertices:
					_state.set_damping(v, BladeState.SEVERED_DRAG)
			_drivers = _surviving_drivers(_drivers, _state, _gate)
			_chunk_start = severed_at
		if budget > 0:
			budget -= count
			if budget <= 0:
				break
	if _chunk_start < _total_steps:
		return false
	_finish()
	return true


func _finish() -> void:
	_done = true
	_state.speed_history = _speed_history
	# One coherent timeline over every batch. The record carries each hit's
	# structural key and every peer compiles its own seconds from it.
	_outcome.schedule = OutcomeSchedule.compile(_outcome)
	# The AI's shape-risk signal: how many of the attacker's own vertices this
	# swing actually DESTROYED. Pops only (#799) — a vertex that merely lost its
	# path to the handle coasts on in this same trajectory and is not a loss.
	_outcome.popped_nodes += _gate.result.vertex_pop_count()


## Mint, crit and LAND one sample's contacts, appending what landed to
## [param outcome] and [param hits].
##
## [b]The interleave is sim / scan / LAND, not sim / scan / gate.[/b] The pop
## gate is reached from [method BladeDamageInstance.land_on] inside
## [method OutcomeApplier.apply]'s walk — only APPLYING produces the world the
## next pop decision has to read. This is the per-batch idiom #186's free-flight
## round already used (sub-outcome → compile → same crit rng → apply → merge),
## in a loop; no suspendable applier is needed.
func _land_batch(
		outcome: AttackOutcome,
		batch: Array[BladeHitEvent],
		state: BladeState,
		gate: BladePopResolver.LiveGate,
		world: CombatWorld,
		rng: RandomNumberGenerator,
		hits: Array[DamageInstance]) -> void:
	var sub := AttackOutcome.new()
	sub.cadence = ScheduleEntry.Cadence.SWING
	sub.resolve_seed = _ctx.resolve_seed
	for ev in batch:
		# An EDGE contact produces no DamageInstance at all (ADR 0005): edges
		# give rigidity, nodes deal damage. It stays in `last_events` — it is a
		# real contact, and #781's bunker break is its consumer — but it buys no
		# crit roll, no schedule entry and no AttackRecord line, because there
		# is no damage for any of those to be about.
		if ev.is_edge_hit():
			continue
		# #502: no pre-filtering by pops/allocation here — every VERTEX event
		# becomes a candidate DamageInstance. Whether it actually lands is
		# BladeDamageInstance.land_on's call, live, when OutcomeApplier
		# consumes it (docs/domain/attack-timeline.md). There is no
		# disconnection scale (#186 acceptance 3): a coasting vertex carries the
		# SAME coefficient a driven one would, and #779's speed curve — applied
		# off `ev.speed`, which for a coasting vertex is its coasting speed — is
		# the only thing that makes it hit for less. Or, flung hard, for more.
		var di := BladeDamageInstance.new(ev, gate)
		di.amount = state.vertex_damage[ev.particle_idx]
		di.type = DamageInstance.Type.PHYSICAL
		di.target = ev.target as SkillNode
		di.origin = _ctx.origin
		di.source = _ctx.hit_source
		di.attacker = _ctx.attacker
		# Melee is #543's honest caveat: its structural parameter IS continuous
		# time the sim produced, so it is NORMALIZED against the swing rather
		# than "not timing at all". The compiler scales it back out by
		# [member PresentationTempo.swing_duration], which is what lets the
		# picture be stretched without re-simulating the blade.
		di.structural_key = ev.t / maxf(0.001, _ctx.swing_duration)
		sub.hits.append(di)
	if sub.hits.is_empty():
		return
	sub.schedule = OutcomeSchedule.compile(sub)
	CritRoll.decide_all(sub, rng)
	# Melee selects on physics, so nothing above read `world`: every live read
	# it makes is inside `BladeDamageInstance.land_on` -> `LiveGate.admit`,
	# which is what this pass runs. Un-awaited — see the same call in
	# [method RangedAttackPlan.resolve_against] for why that is safe.
	OutcomeApplier.apply(sub, world)
	for hit in sub.hits:
		outcome.hits.append(hit)
		hits.append(hit)


## [param drivers] minus every driver on a vertex the swing has stopped
## driving — a destroyed one (frozen; a driver would move a corpse) and a
## COASTING one (severed from the handle; a driver would keep swinging it as if
## the arm were still attached). Everything else is untouched, so an unsevered
## swing gets its own list back.
static func _surviving_drivers(
		drivers: Array[BladeDriver],
		state: BladeState,
		gate: BladePopResolver.LiveGate) -> Array[BladeDriver]:
	var coasting: Dictionary = {}
	for severance in gate.result.severances:
		for v in severance.vertices:
			coasting[v] = true
	var kept: Array[BladeDriver] = []
	for d in drivers:
		var ad := d as BladeArcDriver
		if ad != null and (state.is_vertex_removed(ad.particle) or coasting.has(ad.particle)):
			continue
		kept.append(d)
	return kept
