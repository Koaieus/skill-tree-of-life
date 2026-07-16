@tool
class_name MagicBounceCoordinator
extends VFXCoordinator

## Plays a multi-hop spell's visual sequence. Walks [member AttackOutcome.timeline]
## ([PropagationEvent]s), groups it by [member PropagationEvent.beat], and fires
## one wave per beat on a fixed clock: beat N spawns at
## [code]t = N * per_hop_duration[/code] relative to [method play].
##
## ## The clock is the ground truth
##
## Animations do NOT gate the clock. Each spawned [Projectile] is given
## [member per_hop_duration] as its flight budget so the visual lands
## roughly when the next wave fires — but if a visual lingers past its
## window (long trail, slow fade) it keeps playing in parallel with the
## next hop's projectiles. That parallel-stacking IS the look for branchy
## spells (fork lightning). Awaiting "previous projectile finished" would
## let a slow fork hold up the propagation; we don't do that.

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")

## Fired immediately before each beat's events are played. Tests assert the
## emission cadence here; gameplay can use it for SFX cues. `events_in_wave`
## counts every [PropagationEvent] on the beat (landings + CANCELs), which
## equals the hit count whenever every event lands damage.
signal wave_started(hop_index: int, events_in_wave: int)

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL
## Seconds between hop waves. Sets the cadence of the BFS clock.
@export var per_hop_duration: float = 0.4
## Per-projectile flight duration. Should be ≤ [member per_hop_duration]
## so the ball lands before the next wave fires; set slightly shorter for
## a small "landed, then next hop" beat.
@export var flight_time: float = 0.35
@export var face_velocity: bool = true


# `pending` is Array[int] so closures can mutate it (lambdas capture locals
# by value). Tracks projectiles still in-flight so we don't queue_free this
# coordinator before its children drain.
func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	# Guard on the timeline, not `hits`: a pure-utility spell (base_damage 0)
	# lands zero-damage events that carry no hit — it must still render its path.
	if outcome == null or outcome.timeline.is_empty():
		return
	var waves := _group_by_beat(outcome.timeline)
	var beats: Array = waves.keys()
	beats.sort()
	var pending: Array[int] = [0]
	for i in beats.size():
		var beat := int(beats[i])
		var wave: Array = waves[beat]
		wave_started.emit(beat, wave.size())
		for ev_v in wave:
			_play_event(ev_v, pending)
		if i < beats.size() - 1:
			await get_tree().create_timer(per_hop_duration).timeout
	while pending[0] > 0:
		await get_tree().process_frame


func _group_by_beat(timeline: Array[PropagationEvent]) -> Dictionary:
	var waves: Dictionary = {}
	for ev in timeline:
		if not waves.has(ev.beat):
			waves[ev.beat] = []
		waves[ev.beat].append(ev)
	return waves


# Plays one event: a projectile travels origin→target and applies the event's
# hit (if any) on arrival. CANCEL events land no projectile this cut — the
# dissipate visual and the verb→ProjectilePath mapping are follow-on work.
func _play_event(ev: PropagationEvent, pending: Array[int]) -> void:
	if ev.verb == PropagationEvent.Verb.CANCEL:
		return
	if ev.origin == null or ev.target == null:
		return
	var proj := Projectile.new()
	proj.path = _resolved_path()
	proj.visual_scene = visual_scene
	proj.flight_time = flight_time
	proj.face_velocity = face_velocity
	proj.crit_tier = ev.crit_tier
	add_child(proj)
	pending[0] += 1
	var hit: DamageInstance = ev.damage
	proj.arrived.connect(func() -> void:
		if hit != null and hit.target != null:
			hit.target.take_damage(hit.amount, hit))
	proj.tree_exiting.connect(func() -> void:
		pending[0] -= 1)
	proj.launch(ev.origin.global_position, ev.target.global_position, 0.0)


func _resolved_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()
