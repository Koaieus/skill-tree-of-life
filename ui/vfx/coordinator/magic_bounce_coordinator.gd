@tool
class_name MagicBounceCoordinator
extends VFXCoordinator

## Plays a multi-hop spell's visual sequence. Walks [member AttackOutcome.timeline]
## ([PropagationEvent]s), groups it by [member PropagationEvent.beat], and fires
## one wave per beat on a fixed clock read off the cast's compiled
## [OutcomeSchedule] (#543): beat N impacts at
## [code]lead_in + N * beat_interval[/code] relative to [method play].
##
## ## The clock is the ground truth
##
## Animations do NOT gate the clock. Each spawned [Projectile] is given
## [member flight_time] as its flight budget so the visual lands
## roughly when the next wave fires — but if a visual lingers past its
## window (long trail, slow fade) it keeps playing in parallel with the
## next hop's projectiles. That parallel-stacking IS the look for branchy
## spells (fork lightning). Awaiting "previous projectile finished" would
## let a slow fork hold up the propagation; we don't do that.
##
## ## Three-clocks timing
##
## Impact is pinned to the beat, not to launch (#201). Projectiles are
## spawned early (one [method OutcomeSchedule.lead_in] ahead of the beat) so
## they arrive exactly at the beat. The visual's own windup/linger is free to
## start before and outlive impact — the coordinator only gates on the wave
## clock.
##
## [b]Both numbers come from the schedule, not from an export here[/b] (#543
## D3). They used to exist twice — as `const`s in [SpellResolver] stamped into
## the model's landing times, and as `@export`s on this node driving the
## picture — deliberately unwired, with a documented "retune either and
## re-check both" tax. [PresentationTempo] is now their single home and
## [method OutcomeSchedule.compile] their only reader, so the mutation clock
## and the picture cannot drift apart.
##
## ## Verb → ProjectilePath mapping
##
## Each [PropagationEvent.Verb] can carry its own path and visual:
##   * [member jump_path] / [member jump_visual]  — JUMP (the seed)
##   * [member edge_path] / [member edge_visual]  — EDGE (along the edge)
##   * [member self_loop_path] / [member self_loop_visual] — SELF_LOOP
##   * [member cancel_visual] — CANCEL dissipate (no projectile path)
## Unset slots fall back to [member projectile_path] / [member visual_scene],
## then to built-in defaults.
##
## ## Pure observer (#474)
##
## [member PropagationEvent.hits] have ALREADY landed by the time [method play]
## runs — BattleSystem applies the whole [AttackOutcome] synchronously before
## any VFX await starts. This
## coordinator never calls take_damage/heal_damage; it only renders.

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")
const _DEFAULT_CANCEL: PackedScene = preload("res://ui/vfx/projectile/visual/cancel_dissipate.tscn")

## Fired immediately at each beat — the impact moment for projectiles that
## were spawned early. Tests assert the emission cadence here; gameplay can
## use it for SFX cues. `events_in_wave` counts every [PropagationEvent] on
## the beat (landings + CANCELs).
signal wave_started(hop_index: int, events_in_wave: int)

## Fallback SHAPE, used only for an outcome that arrives with no compiled
## [member AttackOutcome.schedule] — a hand-built fixture, or a preview built
## outside a resolve. On the real path the spell's own
## [member SpellDef.tempo] already rode into the schedule at resolve time and
## this is never consulted; null falls back to
## [method PresentationTempo.shared_default].
##
## [b]Not a place to retune a spell.[/b] Author the `.tres` the [SpellDef]
## points at — that is the one both the model and the picture read.
@export var tempo: PresentationTempo = null
@export var face_velocity: bool = true

# -- Verb → path slots --------------------------------------------------------
## Path for [constant PropagationEvent.Verb.JUMP] (the seed arc). Defaults to
## [member projectile_path] → [BezierArcPath].
@export var jump_path: ProjectilePath
## Path for [constant PropagationEvent.Verb.EDGE] (along the graph edge).
## Defaults to [member projectile_path] → [BezierArcPath].
@export var edge_path: ProjectilePath
## Path for [constant PropagationEvent.Verb.SELF_LOOP] (leave-and-return arc).
## Defaults to [member projectile_path] → [BezierArcPath].
@export var self_loop_path: ProjectilePath

# -- Verb → visual slots ------------------------------------------------------
@export var jump_visual: PackedScene
@export var edge_visual: PackedScene
@export var self_loop_visual: PackedScene
## Visual for [constant PropagationEvent.Verb.CANCEL] — a one-shot dissipate/pop
## at the target node. No projectile path; spawns in place. Defaults to
## [CancelDissipate]. Set to null to disable cancel visuals entirely.
@export var cancel_visual: PackedScene = _DEFAULT_CANCEL

# -- Legacy fallback exports (kept for existing scenes/tres) ------------------
## Fallback path when no per-verb path is set.
@export var projectile_path: ProjectilePath
## Fallback visual when no per-verb visual is set.
@export var visual_scene: PackedScene = _DEFAULT_VISUAL

# The `waves` / beat-index / `pending` triple this coordinator schedules with
# wants to be a per-wave object rather than three parallel locals — #722.

var _caster_tint: Color = Color.WHITE
## Which way the cast currently playing turns, and the signed paths built for
## it. Both are per-cast state resolved in [method play] — see #708.
var _turn_sign: float = 0.0
var _handed_paths: Dictionary = {}  ## Verb -> ProjectilePath


func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	# Guard on the timeline, not `hits`: a pure-utility spell (power 0)
	# lands zero-damage events that carry no hit — it must still render its path.
	if outcome == null or outcome.timeline.is_empty():
		return
	# Whoever resolved this already compiled one; compiling here covers a
	# hand-built outcome and is idempotent either way.
	if outcome.schedule == null:
		outcome.schedule = OutcomeSchedule.compile(outcome, tempo)
	var schedule: OutcomeSchedule = outcome.schedule
	# Resolved ONCE per cast, not per event: a spell has exactly one caster,
	# and a CANCEL / pure-utility event carries no hit to read an attacker off
	# at all — so a per-event read would drop identity on precisely the events
	# that already carry the least information.
	_caster_tint = _resolve_caster_tint(outcome)
	# Once per cast, not per bolt: handedness is constant for a whole cast, so
	# the signed path resources below are built at most once per verb and no
	# projectile ever duplicates one (#708).
	_turn_sign = _resolve_turn_sign(outcome)
	_handed_paths.clear()
	var entry_of := _entries_by_event(schedule)
	var waves := _group_by_beat(outcome.timeline)
	var beats: Array = waves.keys()
	beats.sort()
	var pending: Array[int] = [0]
	# AWAIT the timeline before draining. `_play_three_clocks` is a coroutine,
	# so an un-awaited call returns at its first timer with only wave 0 spawned
	# — and then the drain below exits as soon as wave 0's pending count hits
	# zero, which can happen before wave 1 is even spawned. Two ways in:
	# `beat_interval > 2 * launch_to_impact` (wave 0 lands during the early
	# sleep), or a wave 0 that increments nothing at all — `_play_projectile`
	# bails on a null endpoint and `_play_cancel` on a missing visual, so a
	# first beat made only of those leaves `pending` at 0 and the drain exits
	# on the first check, at ANY tuning.
	#
	# `play()` returning is what makes AttackVFX free this coordinator, taking
	# every later beat's projectiles with it: the spell would silently stop
	# rendering partway down its own timeline (damage/heal are already
	# applied by BattleSystem before play() ever runs — see #474 — so what's
	# at stake here is purely the visual, not a dropped mutation).
	await _play_three_clocks(schedule, entry_of, waves, beats, pending)
	while pending[0] > 0:
		await get_tree().process_frame


## Three-clocks playback: projectiles are spawned early ([code]beat_time - launch_to_impact[/code])
## so impact lands on the beat. [method wave_started] fires AT the beat.
func _play_three_clocks(schedule: OutcomeSchedule, entry_of: Dictionary,
		waves: Dictionary, beats: Array, pending: Array[int]) -> void:
	var interval: float = schedule.beat_interval()
	# Floored at a tick rather than at 0: `create_timer(0.0)` is an error, and
	# a lead-in of exactly zero is a legal authoring choice.
	var flight: float = maxf(0.001, schedule.lead_in())

	for i in beats.size():
		var beat := int(beats[i])
		var wave: Array = waves[beat]

		if i == 0:
			# The seed's own flight was the one hop nobody waited for. Beat 0
			# used to be announced synchronously with `play()` — same instant
			# its projectile was spawned — so the first propagation left the
			# target before the bolt travelling toward it had arrived. Every
			# LATER beat was already spawned `flight` early and announced on
			# arrival; beat 0 is now the same shape, which costs one `flight`
			# of lead-in and puts the whole spell in cause-then-effect order.
			for ev_v in wave:
				_play_event(ev_v, entry_of, flight, pending)
			await get_tree().create_timer(flight).timeout

		# #504: no `_show_presentation` pass anymore. The wave's hits land on
		# the applier's beat clock, so the HP bar, node tint and damage number
		# all move off the model as the bolt arrives — this coordinator no
		# longer re-announces what already happened. `wave_started` stays: it is
		# the animation's own cadence signal, which tests assert on.
		#
		# "As the bolt arrives" used to be an arithmetic claim whose two halves
		# were maintained by hand in two files. Since #543 it is true by
		# construction: impact here is `lead_in + N * beat_interval` read off
		# the schedule, and the applier waits that same schedule's
		# `arrive_at`. One number, so there is nothing left to re-check.
		wave_started.emit(beat, wave.size())

		if i < beats.size() - 1:
			var next_wave: Array = waves[int(beats[i + 1])]
			var early: float = maxf(0.0, interval - flight)
			if early > 0.0:
				await get_tree().create_timer(early).timeout
			for ev_v in next_wave:
				_play_event(ev_v, entry_of, flight, pending)
			var remaining: float = maxf(0.0, interval - early)
			if remaining > 0.0:
				await get_tree().create_timer(remaining).timeout


## Presentation-clock reveal (#479/#481), fired AT the beat — magic's fixed
## propagation clock already IS the arrival schedule (impact is pinned to
## the beat per the three-clocks model above), so no extra timer is needed
## here unlike ranged's per-shot [member HitInstance.arrival_time]. Pure
func _group_by_beat(timeline: Array[PropagationEvent]) -> Dictionary:
	var waves: Dictionary = {}
	for ev in timeline:
		if not waves.has(ev.beat):
			waves[ev.beat] = []
		waves[ev.beat].append(ev)
	return waves


func _play_event(ev: PropagationEvent, entry_of: Dictionary, flight: float,
		pending: Array[int]) -> void:
	match ev.verb:
		PropagationEvent.Verb.CANCEL:
			_play_cancel(ev, pending)
		_:
			_play_projectile(ev, entry_of, flight, pending)


func _play_projectile(ev: PropagationEvent, entry_of: Dictionary, flight: float,
		pending: Array[int]) -> void:
	if ev.target == null:
		return
	for i in _arc_indices_for(ev):
		var origin: SkillNode = ev.predecessors[i] if i >= 0 else ev.origin
		_spawn_projectile(ev, origin, _share_at(ev, i), entry_of.get(ev, null), flight, pending)


## Event -> its [ScheduleEntry]. Identity-keyed, because two landings on one
## node in one beat are distinct events with equal field values (the same
## reason [method AttackRecord.capture] keys its hit index by identity).
func _entries_by_event(schedule: OutcomeSchedule) -> Dictionary:
	var by_event: Dictionary = {}
	for entry in schedule.entries:
		if entry.event != null:
			by_event[entry.event] = entry
	return by_event


## One inbound bolt per converging predecessor (#542) — a fork-then-reconverge
## lands one impact ([code]docs/domain/attack-timeline.md[/code] / D2 on #542)
## but should draw every branch that fed it, not just [member
## PropagationEvent.origin].
##
## Returns INDICES into [member PropagationEvent.predecessors] rather than the
## nodes themselves, because the index is what keeps each bolt paired with its
## own [member PropagationEvent.incident_shares] entry (#708) — resolving to
## nodes first and looking the weight up afterwards is exactly how the two
## arrays would drift.
##
## [code]-1[/code] means "no predecessor to index": the single-`origin` fallback
## the overwhelming majority of events take (JUMP, SELF_LOOP, a plain
## unconverged EDGE), which all carry ≤1 predecessor and draw one bolt either way.
func _arc_indices_for(ev: PropagationEvent) -> PackedInt32Array:
	var out := PackedInt32Array()
	if ev.predecessors.size() > 1:
		for i in ev.predecessors.size():
			if ev.predecessors[i] != null:
				out.append(i)
		if out.size() > 1:
			return out
		out.clear()
	if ev.origin != null:
		out.append(-1)
	return out


## The share the bolt at [param index] is carrying, or 1.0 for "undivided".
##
## The fallback is deliberately NOT [code]incident_shares[0][/code]. A merged
## event whose predecessors filtered down to one non-null entry still carries
## several shares, and index 0 need not be the survivor's — reading it anyway
## would pair a bolt with another arc's weight, which is worse than not weighting
## it at all because it is wrong rather than merely absent.
func _share_at(ev: PropagationEvent, index: int) -> float:
	if index >= 0 and index < ev.incident_shares.size():
		return ev.incident_shares[index]
	if ev.incident_shares.size() == 1:
		return ev.incident_shares[0]
	return 1.0


## The cast's handedness, read off the first landing that reports one (#708).
## 0.0 = no handedness, which is every spell but Cyclone and also Cyclone's own
## seed, since a JUMP is not a turn.
func _resolve_turn_sign(outcome: AttackOutcome) -> float:
	for ev in outcome.timeline:
		if not is_zero_approx(ev.turn_sign):
			return ev.turn_sign
	return 0.0


## The authored path, bowed to the side the storm actually turns.
##
## The authored amplitude expresses the +1 look, so a positive or absent sign
## hands back the shared resource untouched and nothing allocates. A negative
## one needs a [WavePath] whose [member WavePath.handedness] is flipped — and
## because [ProjectilePath] resources are SHARED and live, that has to be a
## duplicate rather than a write. Cached per verb and cleared per cast, so a
## whole hex wheel costs at most two duplicates, never one per bolt.
func _handed_path(verb: PropagationEvent.Verb, path: ProjectilePath) -> ProjectilePath:
	if _turn_sign >= 0.0 or path == null or not (path is WavePath):
		return path
	if not _handed_paths.has(verb):
		var flipped: WavePath = (path as WavePath).duplicate()
		flipped.handedness = -absf(flipped.handedness)
		_handed_paths[verb] = flipped
	return _handed_paths[verb]


func _spawn_projectile(ev: PropagationEvent, origin: SkillNode, share: float,
		entry: ScheduleEntry, flight: float, pending: Array[int]) -> void:
	var proj := Projectile.new()
	proj.path = _handed_path(ev.verb, _resolved_path(ev.verb))
	proj.visual_scene = _resolved_visual(ev.verb)
	proj.flight_time = flight
	proj.face_velocity = face_velocity
	proj.crit_tier = ev.max_crit_tier()
	# The whole render context, not just the crit integer (#543 D6). Set
	# BEFORE `launch`, which is what instantiates the visual and forwards it.
	proj.context = entry
	add_child(proj)
	pending[0] += 1
	proj.tree_exiting.connect(func() -> void:
		pending[0] -= 1)
	proj.launch(origin.global_position, ev.target.global_position, 0.0)
	# Tint hook, mirroring ArrowVolleyCoordinator exactly (#663 D4): `launch`
	# instantiates the visual synchronously as the projectile's first child, so
	# stamping right after is what lets the body read the caster's colour on its
	# FIRST draw rather than popping a frame later. Visuals with no `tint` field
	# ignore it — that is the duck-typed visual contract, not a missing guard.
	if proj.get_child_count() > 0:
		var v: Node = proj.get_child(0)
		if "tint" in v:
			v.set("tint", _caster_tint)
		# Same hook, same guard: a visual that is a bare BoltBody, or a spell
		# that never opted into weighting, simply ignores it.
		if "arc_weight" in v:
			v.set("arc_weight", share)


## The caster's identity colour for the cast currently playing, resolved in
## [method play]. White means "no attacker named a colour" — the documented
## no-identity fallback, never a hand-picked default.
##
## This existed for ranged since #507 and was simply absent on the magic path
## until #671/#672 authored the first spell bodies that read it, so every
## spell rendered neutral-white. `docs/domain/spell-vfx-kit.md` already
## described the stamp as if it were here; now it is.
func _resolve_caster_tint(outcome: AttackOutcome) -> Color:
	for hit in outcome.hits:
		if hit.attacker != null:
			return hit.attacker.color
	return Color.WHITE


func _play_cancel(ev: PropagationEvent, pending: Array[int]) -> void:
	var scene := _resolved_cancel_visual()
	if scene == null:
		return
	var node := scene.instantiate()
	# `global_position` only exists on Node2D — a `cancel_visual` overridden
	# with a Control- or Node-rooted scene would crash on the assignment, on an
	# untyped local that gives no hint it could.
	var placed := node as Node2D
	if placed != null and ev.target != null:
		placed.global_position = ev.target.global_position
	add_child(node)
	pending[0] += 1
	node.tree_exiting.connect(func() -> void:
		pending[0] -= 1)
	if node.has_signal(&"finished"):
		node.finished.connect(func() -> void:
			node.queue_free())
	else:
		var t := create_tween()
		t.tween_interval(0.5)
		t.finished.connect(func() -> void:
			node.queue_free())


# -- Path resolution ----------------------------------------------------------

func _resolved_path(verb: PropagationEvent.Verb) -> ProjectilePath:
	var path: ProjectilePath = null
	match verb:
		PropagationEvent.Verb.JUMP:
			path = jump_path
		PropagationEvent.Verb.EDGE:
			path = edge_path
		PropagationEvent.Verb.SELF_LOOP:
			path = self_loop_path
	if path != null:
		return path
	return _default_path()


func _default_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()


# -- Visual resolution --------------------------------------------------------

func _resolved_visual(verb: PropagationEvent.Verb) -> PackedScene:
	var vis: PackedScene = null
	match verb:
		PropagationEvent.Verb.JUMP:
			vis = jump_visual
		PropagationEvent.Verb.EDGE:
			vis = edge_visual
		PropagationEvent.Verb.SELF_LOOP:
			vis = self_loop_visual
	if vis != null:
		return vis
	if visual_scene != null:
		return visual_scene
	return _DEFAULT_VISUAL


func _resolved_cancel_visual() -> PackedScene:
	return cancel_visual
