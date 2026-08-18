@tool
class_name MagicBounceCoordinator
extends VFXCoordinator

## Plays a multi-hop spell's visual sequence. Walks [member AttackOutcome.timeline]
## ([PropagationEvent]s), groups it by [member PropagationEvent.beat], and fires
## one wave per beat on a fixed clock: beat N spawns at
## [code]t = N * beat_interval[/code] relative to [method play].
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
## spawned early ([code]beat_time - launch_to_impact[/code]) so they arrive
## exactly at the beat. The visual's own windup/linger is free to start
## before and outlive impact — the coordinator only gates on the wave clock.
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
## [member PropagationEvent.damage] / [member PropagationEvent.heal] have
## ALREADY landed by the time [method play] runs — BattleSystem applies the
## whole [AttackOutcome] synchronously before any VFX await starts. This
## coordinator never calls take_damage/heal_damage; it only renders.

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")
const _DEFAULT_CANCEL: PackedScene = preload("res://ui/vfx/projectile/visual/cancel_dissipate.tscn")

## Fired immediately at each beat — the impact moment for projectiles that
## were spawned early. Tests assert the emission cadence here; gameplay can
## use it for SFX cues. `events_in_wave` counts every [PropagationEvent] on
## the beat (landings + CANCELs).
signal wave_started(hop_index: int, events_in_wave: int)

## Seconds between beats. Was [code]per_hop_duration[/code] — renamed for the
## three-clocks model where "hop" conflated launch and arrival (#201).
@export var beat_interval: float = 0.4
## Per-projectile flight duration (launch → impact). Must be ≤ [member beat_interval]
## for impact to align with the beat. Renamed from [code]per_hop_duration[/code]'s
## old companion [code]flight_time[/code]; same semantics.
@export var launch_to_impact: float = 0.35
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

class Beat extends RefCounted:
	var wave: int
	var events: Array[PropagationEvent]
	
	# TODO: think through a class decomposition instead of working with `waves, beats, pending`
	
	# static var pending: int = 0
	# TODO: static.. might not be the solution here. but the `pending int[]` array
	# seems to be used as some kind of context, this whole thing smells and i think we are
	# like 1~2 extra inner classes away from could clean this all up a bit typed and well

func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	# Guard on the timeline, not `hits`: a pure-utility spell (power 0)
	# lands zero-damage events that carry no hit — it must still render its path.
	if outcome == null or outcome.timeline.is_empty():
		return
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
	await _play_three_clocks(waves, beats, pending)
	while pending[0] > 0:
		await get_tree().process_frame


## Three-clocks playback: projectiles are spawned early ([code]beat_time - launch_to_impact[/code])
## so impact lands on the beat. [method wave_started] fires AT the beat.
func _play_three_clocks(waves: Dictionary, beats: Array, pending: Array[int]) -> void:
	var interval: float = maxf(0.001, beat_interval)
	var flight: float = clampf(launch_to_impact, 0.001, interval)

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
				_play_event(ev_v, pending)
			await get_tree().create_timer(flight).timeout

		wave_started.emit(beat, wave.size())
		_show_presentation(wave)

		if i < beats.size() - 1:
			var next_wave: Array = waves[int(beats[i + 1])]
			var early: float = maxf(0.0, interval - flight)
			if early > 0.0:
				await get_tree().create_timer(early).timeout
			for ev_v in next_wave:
				_play_event(ev_v, pending)
			var remaining: float = maxf(0.0, interval - early)
			if remaining > 0.0:
				await get_tree().create_timer(remaining).timeout


## Presentation-clock reveal (#479/#481), fired AT the beat — magic's fixed
## propagation clock already IS the arrival schedule (impact is pinned to
## the beat per the three-clocks model above), so no extra timer is needed
## here unlike ranged's per-shot [member DamageInstance.arrival_time]. Pure
## observer: [member PropagationEvent.damage] already landed synchronously
## in BattleSystem._apply_outcome (#474); this only tells presentation-only
## subscribers (HP bar, node tint, death VFX) the hit visually arrived.
func _show_presentation(wave: Array) -> void:
	for ev_v in wave:
		var ev := ev_v as PropagationEvent
		if ev == null or ev.damage == null or ev.target == null:
			continue
		Events.damage_shown.emit(ev.target, ev.damage.effective_amount)
		if not ev.target.is_allocated():
			Events.node_death_shown.emit(ev.target)


func _group_by_beat(timeline: Array[PropagationEvent]) -> Dictionary:
	var waves: Dictionary = {}
	for ev in timeline:
		if not waves.has(ev.beat):
			waves[ev.beat] = []
		waves[ev.beat].append(ev)
	return waves


func _play_event(ev: PropagationEvent, pending: Array[int]) -> void:
	match ev.verb:
		PropagationEvent.Verb.CANCEL:
			_play_cancel(ev, pending)
		_:
			_play_projectile(ev, pending)


func _play_projectile(ev: PropagationEvent, pending: Array[int]) -> void:
	if ev.origin == null or ev.target == null:
		return
	var proj := Projectile.new()
	proj.path = _resolved_path(ev.verb)
	proj.visual_scene = _resolved_visual(ev.verb)
	proj.flight_time = launch_to_impact
	proj.face_velocity = face_velocity
	proj.crit_tier = ev.crit_tier
	add_child(proj)
	pending[0] += 1
	proj.tree_exiting.connect(func() -> void:
		pending[0] -= 1)
	proj.launch(ev.origin.global_position, ev.target.global_position, 0.0)


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
