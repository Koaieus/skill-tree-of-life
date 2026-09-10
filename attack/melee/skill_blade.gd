@tool
class_name SkillBlade
extends Node2D

## Visual wrapper around a BladeState + BladeTrajectory. Owns the BladeNode
## and BladeEdge visuals; replays a trajectory by writing positions onto
## them frame-by-frame. Pure visuals — hit detection is the deterministic
## BladeHitScan over the trajectory, not Godot collision overlap.
##
## `@tool` because the melee sandbox tab (`addons/melee_sandbox/`) builds and
## swings real blades inside the editor. Nothing here auto-drives: a swing only
## happens when someone calls [method play], which keeps it on the live side of
## the "auto-tick = played; explicit-step = live" line
## (docs/domain/sandbox-framework.md).

## Emitted during non-ghost playback at the scheduled time of each hit event.
## hitter_idx is the particle or edge index; is_edge distinguishes the two.
signal hit(hitter_idx: int, is_edge: bool, target: SkillNode, t: float, damage: float)
signal playback_finished

## How far below its authored tier a blade part sits while forming (#559) — a
## VALUE dimmer on `modulate`, so the [BladeStyle] tiers underneath are dimmed
## and restored rather than re-authored (`.claude/rules/hdr-color.md`). At 0.45
## an [constant Emissive.VALUE] rim lands well under the bloom threshold, which
## is the whole point: the blade powers UP.
const _FORM_DIM: float = 0.45
## Scale a vertex pops in from.
const _FORM_SCALE: float = 0.4
## Scale an addon stamp punches to.
const _STAMP_SCALE: float = 1.22

const SCENE := preload("res://attack/melee/skill_blade.tscn")
const BLADE_NODE := preload("res://attack/melee/blade_node.tscn")
const BLADE_EDGE := preload("res://attack/melee/blade_edge.tscn")
## An inherited scene of #835's `shatter_field.tscn`, material overridden to
## `blade_shard_material.tres` (`resource_local_to_scene`, so every
## `instantiate()` — one per SkillBlade — gets its own uniform set rather than
## scrubbing together). See `get_shard_field`.
const BLADE_SHARD_FIELD := preload("res://attack/melee/blade_shard_field.tscn")

@export var owned_by: Entity

## Look profile pushed onto every [BladeNode] / [BladeEdge] this blade spawns
## (#256). One resource per blade, so a sandbox can retune the whole swing live.
@export var style: BladeStyle = BladeNode.DEFAULT_STYLE:
	set(value):
		style = value
		_apply_style()

## The swing's pop outcome, set by the caller BEFORE [method play] when one is
## known ([member MeleeAttackPlan.last_pops]). Vertices it reports dead go
## [member BladeNode.death_progress] from 0 to 1 across [member BladeStyle.pop_window]
## starting at exactly the `t` they died (#787, replacing #256's de-lit
## interim), and spawn their shards into [member _shard_field] the frame
## playback crosses that `t`. Null (the preview loop) means nothing ever dies.
##
## Read, never derived: the blade must not decide who died. That answer belongs
## to [BladePopResolver], which the same swing's `resolve()` already ran.
var pop_result: BladePopResolver.Result = null

## Mirror of [member MeleeAttackPlan.swing_cw]. Set by [MeleePreview] before
## [method simulate] so the live blade swings in the same direction the plan's
## resolve() simulated.
var swing_cw: bool = false

var state: BladeState
var trajectory: BladeTrajectory

var _node_visuals: Array[BladeNode] = []
var _edge_visuals: Array[BladeEdge] = []
var _nodes_container: Node2D
var _edges_container: Node2D
## #787's shard field, one per blade — mounted directly under THIS node
## (`Nodes`/`Edges`'s sibling), which is the static one: nothing ever writes
## `SkillBlade`'s own transform, only its children's (`BladeNode.global_position`
## each frame). A field under a moving `BladeNode` would re-seed its fracture
## pattern every frame instead (`ui/vfx/shatter/shatter_field.gd`'s class docs).
var _shard_field: ShatterField
var _active_tween: Tween
## Pending shard spawns for the CURRENT playback: `.x` = the vertex's dead_at,
## `.y` = its particle index, ascending by `.x` (Vector2's default sort order),
## rebuilt from [member pop_result] on every [method play] and on every
## backward seek — the same "pending, drained once" shape [method play]'s hit
## events already use. See [method _apply_playback_frame].
var _pending_pops: PackedVector2Array = PackedVector2Array()
## The trajectory time [method _apply_playback_frame] was last called with —
## how a backward seek (a scrub) is detected, since nothing else here
## accumulates (`.claude/rules/presentation-clock.md`).
var _last_frame_t: float = -INF
## The SkillNodes [method build_from_skill_nodes] was last built from, in
## [BladeState] particle order. Only the wind-up reads it.
var _source_nodes: Array[SkillNode] = []
## The single Tween driving the wind-up (#559). One tween with parallel,
## delayed tweeners rather than a coroutine chain, so [method stop] can kill
## the whole sequence in one call and [method play] cannot end up fighting a
## leftover form tweener for `modulate`.
var _form_tween: Tween


func _ready() -> void:
	_edges_container = get_node_or_null("Edges")
	if _edges_container == null:
		_edges_container = Node2D.new()
		_edges_container.name = "Edges"
		add_child(_edges_container)
	_nodes_container = get_node_or_null("Nodes")
	if _nodes_container == null:
		_nodes_container = Node2D.new()
		_nodes_container.name = "Nodes"
		add_child(_nodes_container)
	_shard_field = get_node_or_null("ShardField") as ShatterField
	if _shard_field == null:
		_shard_field = BLADE_SHARD_FIELD.instantiate() as ShatterField
		_shard_field.name = "ShardField"
		add_child(_shard_field)
	# `style`'s setter can run before this node exists (property
	# deserialization on instantiate) and no-ops on a null field; catch it up
	# now that one exists.
	_push_shard_look()


## True when the selected node set can form a valid blade.
static func is_valid_selection(
		skill_nodes: Array,
		pivot: SkillNode,
		induced_edges: Array) -> bool:
	return skill_nodes.size() >= 2 \
			and pivot in skill_nodes \
			and induced_edges.size() >= 1


## Construct the blade from a 1:1 copy of the chosen SkillNodes.
## `induced_edges`: Array of [SkillNode, SkillNode] pairs (induced subgraph).
## Call after adding the SkillBlade to the scene tree; safe to call again to
## rebuild for an updated selection (visuals are torn down + rebuilt).
func build_from_skill_nodes(
		skill_nodes: Array[SkillNode],
		pivot: SkillNode,
		induced_edges: Array,
		owner_entity: Entity) -> void:
	owned_by = owner_entity
	# A rebuild is a fresh blade: last swing's deaths must not de-light it, and
	# its shards must not still be flying.
	pop_result = null
	_pending_pops = PackedVector2Array()
	if _shard_field != null:
		_shard_field.clear()
	# Held so the wind-up (#559) can ask which vertices carry an addon without
	# re-deriving it from the plan — [BladeState] deliberately keeps no handle
	# on the SkillNodes it was built from, and `apply_to_blade` below is a pure
	# virtual dispatch that tells us nothing about who dispatched.
	_source_nodes = skill_nodes.duplicate()
	_clear_visuals()
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	var inner_radii: Array[float] = []
	var pivot_idx := 0
	var sn_to_idx: Dictionary = {}
	for i in skill_nodes.size():
		var sn := skill_nodes[i]
		sn_to_idx[sn] = i
		positions.append(sn.global_position)
		radii.append(sn.radius)
		inner_radii.append(sn.inner_radius)
		if sn == pivot:
			pivot_idx = i
	var edges_idx: Array[Vector2i] = []
	for pair in induced_edges:
		edges_idx.append(Vector2i(sn_to_idx[pair[0]], sn_to_idx[pair[1]]))
	state = BladeState.build(positions, pivot_idx, edges_idx, radii, inner_radii)
	# Per-vertex damage is the node's own blade_damage (wielder base merged with
	# any node-local spike modifier) — one localized read per source node.
	for i in skill_nodes.size():
		state.vertex_damage[i] = skill_nodes[i].get_local_value(&"blade_damage")
	# Per-vertex blunting, same localized read (#778) — a spiked vertex carries
	# the SpikeRingAddon's raise to 2, so it reaches BladePopResolver.LiveGate.
	for i in skill_nodes.size():
		state.vertex_blunting[i] = skill_nodes[i].get_local_value(&"blunting")
	# No per-EDGE fill: ADR 0005 — an edge carries no stats. Mirrors the same
	# absence in melee_attack_plan.gd's build_blade_state.
	# Dispatch to addons after BladeState is built so they can append
	# constraints (Clamp's phantom brace). SkillBlade never learns specific
	# addon types — pure virtual dispatch.
	for i in skill_nodes.size():
		for addon in skill_nodes[i].get_addons():
			addon.apply_to_blade(state, i)
	_spawn_visuals()


## Run a swing simulation around the pivot. Returns a fresh trajectory each
## call; safe to invoke repeatedly (state is reset to the descriptor's
## original positions internally via re-build_from_skill_nodes if needed).
## Drivers are auto-built: one BladeArcDriver per pivot-adjacent particle.
## `clock` is the optional Fortification drag clock (#780) — pass
## [method MeleeAttackPlan.build_swing_clock] to make a GHOST preview slow down
## on a wall exactly as the committed swing will. A clock is single-use (it
## banks the zones it has already touched), so a repeating preview loop must
## build a fresh one per cycle. Null keeps the nominal, undragged arc.
func simulate(
		duration: float = 1.2,
		dt: float = BladeSim.DEFAULT_DT,
		iterations: int = BladeSim.DEFAULT_ITERATIONS,
		velocity_iter_ref: float = 0.0,
		clock: BladeSwingClock = null) -> BladeTrajectory:
	var drivers := _build_swing_drivers(duration)
	trajectory = BladeSim.simulate(
			state, drivers, duration, dt, iterations, velocity_iter_ref,
			BladeSim.DEFAULT_SUBSTEPS, true, clock)
	return trajectory


## Tween visual positions through the trajectory. Awaitable.
##   - ghostly=true: translucent modulate, no hit signals emitted
##   - hits: pre-scanned BladeHitEvents emitted at their scheduled t
##   - playback_rate: 1.0 (default) preserves today's real-time pace exactly;
##     0.5 takes twice the wall-clock to play the same trajectory. See the
##     sim/presentation invariant in docs/domain/melee-blade-sim.md — hit
##     scheduling stays in trajectory time regardless of this knob (#619).
##   - duration_override: >= 0.0 overrides [method BladeTrajectory.duration] as
##     the tween's trajectory-time span. #796: a mirror's committed-swing resim
##     may still be stepping when this call starts (`traj.samples` grows in
##     place as it does), so `traj.duration()` would underreport and cut the
##     tween short. [method MeleeAttackPlan.replay_duration] is the real span
##     in that case; every other caller leaves this at -1 and keeps deriving
##     duration from the (already complete) trajectory exactly as before.
func play(
		traj: BladeTrajectory,
		hits: Array[BladeHitEvent] = [],
		ghostly: bool = false,
		playback_rate: float = 1.0,
		duration_override: float = -1.0) -> void:
	if traj == null or traj.samples.is_empty():
		playback_finished.emit()
		return
	# The wind-up hands the blade over here fully formed; anything still in
	# flight (a flare relaxing back down) would keep writing `modulate` under
	# the swing. Settle it rather than race it.
	_finish_form()
	modulate = Color(1.0, 1.0, 1.0, 0.35) if ghostly else Color.WHITE
	# A fresh play() is a fresh clock: drop anything the LAST swing's pool
	# still had in flight (#835's pool caveat — a spawn after the pool is
	# empty re-bases `time_base` to this swing's own spawn times) and
	# re-derive the pending shard spawns from `pop_result` as it stands now.
	if _shard_field != null:
		var pop_style: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
		_shard_field.window = pop_style.pop_window
		_shard_field.flight_start = 0.0
		_shard_field.clear()
	_last_frame_t = -INF
	_rebuild_pending_pops()
	var pending: Array[BladeHitEvent] = hits.duplicate()
	var dur := duration_override if duration_override >= 0.0 else traj.duration()
	# tween_method interpolates the VALUE range [0, dur] linearly over
	# `wall_duration` wall-clock seconds — the callback argument is always
	# trajectory time, never wall-clock time, no matter how the two differ.
	# That mismatch IS the rate knob: _apply_playback_frame and its hit
	# comparisons need no conversion and stay correct at any rate.
	var wall_duration := dur / maxf(playback_rate, 0.0001)
	var tween := create_tween()
	_active_tween = tween
	tween.tween_method(
			_apply_playback_frame.bind(traj, pending, ghostly),
			0.0, dur, wall_duration)
	await tween.finished
	_active_tween = null
	playback_finished.emit()


func _apply_playback_frame(
		t: float,
		traj: BladeTrajectory,
		pending: Array[BladeHitEvent],
		ghostly: bool) -> void:
	# Scrub-safety (#787 acceptance 3): a backward seek is the only thing that
	# can invalidate the shard pool's forward-only assumption (#835's pool
	# caveat) — nothing here otherwise accumulates. Detect it off the LAST `t`
	# this was called with and react exactly as the pool caveat prescribes:
	# clear() + re-drain the pending spawns, never just a smaller `elapsed`.
	if t < _last_frame_t:
		if _shard_field != null:
			_shard_field.clear()
		_rebuild_pending_pops()
	_last_frame_t = t
	var positions := traj.sample(t)
	for i in _node_visuals.size():
		if i < positions.size():
			_node_visuals[i].global_position = positions[i]
		if pop_result != null:
			_node_visuals[i].death_progress = _death_progress_at(i, t)
	if pop_result != null:
		for i in _edge_visuals.size():
			# Edge index into state.edges is stable for the whole swing
			# (#785/#801), and _edge_visuals was spawned in that same order —
			# see _spawn_visuals — so i indexes both alike.
			_edge_visuals[i].severed = pop_result.severed_at.has(i) \
					and t >= pop_result.severed_at[i]
	if _shard_field != null:
		# Set BEFORE draining: spawn_shatter's own rebase check
		# (`elapsed >= _max_expiry`) reads the field's `elapsed`.
		_shard_field.elapsed = t
		while not _pending_pops.is_empty() and _pending_pops[0].x <= t:
			var due := _pending_pops[0]
			_pending_pops = _pending_pops.slice(1)
			if not ghostly:
				# #787 decision 11: the ghost/preview drives death_progress
				# like any swing but spawns no shards.
				_spawn_shard_for(int(roundf(due.y)), due.x, traj)
	while not pending.is_empty() and pending[0].t <= t:
		var ev: BladeHitEvent = pending.pop_front()
		if not ghostly:
			# Edges are live CONTACTS (#785) but deal no damage (ADR 0005):
			# they exist so a bunker cannot slip between two vertices into the
			# blade's interior. A vertex contact carries the coefficient and
			# the speed curve; an edge contact carries 0.
			var is_edge := ev.is_edge_hit()
			var coeff := (
					0.0 if is_edge
					else state.vertex_damage[ev.particle_idx])
			var damage := coeff * _speed_multiplier(ev)
			hit.emit(
					ev.edge_idx if is_edge else ev.particle_idx,
					is_edge, ev.target as SkillNode, ev.t, damage)


## The speed-scaled damage curve (#779), read off [member owned_by]'s board —
## this is the VISUAL playback path (the floater/emit-only site), never the
## authority's real damage. That number comes off [BladeDamageInstance] at
## [MeleeAttackPlan] resolve time; this only has to agree with it so a
## preview/ghost swing shows the same figure the real one will land. Falls
## back to a 1.0 multiplier for an unowned blade (headless fixtures, the
## sandbox's ownerless preview) via [method BladeState.stat_value]'s guard.
## death_progress at trajectory time `t` for vertex `idx` — a pure function
## of [member pop_result], never a stored ramp
## (`.claude/rules/presentation-clock.md`): 0 before the vertex died, then
## `(t - dead_at) / window` clamped to [0, 1]. Called only when [member
## pop_result] is non-null, same gate [method _apply_playback_frame] applied.
func _death_progress_at(idx: int, t: float) -> float:
	if not pop_result.dead_at.has(idx):
		return 0.0
	var dead_t: float = pop_result.dead_at[idx]
	if t < dead_t:
		return 0.0
	var s: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
	return clampf((t - dead_t) / s.pop_window, 0.0, 1.0)


## Rebuilds [member _pending_pops] from [member pop_result]: one entry per
## `dead_at` vertex, `.x` the death time and `.y` the particle index, sorted
## ascending by time (Vector2's default sort compares `.x` then `.y`) so
## [method _apply_playback_frame] can drain it with the same
## `while pending[0].t <= t` shape [method play]'s hit events already use.
## Called on every [method play] and every backward seek (#835's pool caveat:
## a rewind clears the field, so its pending spawns must be re-derived too).
func _rebuild_pending_pops() -> void:
	_pending_pops = PackedVector2Array()
	if pop_result == null:
		return
	for idx in pop_result.dead_at:
		_pending_pops.append(Vector2(float(pop_result.dead_at[idx]), float(idx)))
	_pending_pops.sort()


## Fragments vertex `idx` into [member _shard_field] at the moment it died
## (#787 decision 5). `dead_t` is trajectory time, matching `traj`'s own
## clock; the field's `elapsed` is already trajectory time too (set by
## [method _apply_playback_frame] just before this is called).
func _spawn_shard_for(idx: int, dead_t: float, traj: BladeTrajectory) -> void:
	if _shard_field == null or idx < 0 or idx >= _node_visuals.size():
		return
	var bn := _node_visuals[idx]
	var s: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
	var tint_color := s.base_for(bn.is_pivot, entity_tint())
	var vel := seed_velocity(traj, idx, dead_t)
	var origin := _shard_field.to_local(bn.global_position)
	_shard_field.spawn_shatter(
			origin, bn.radius, tint_color, vel, dead_t,
			s.pop_shard_count, s.pop_kick_speed)


## The velocity a popped vertex hands its shards (#787 acceptance 4): the last
## MOVING sample pair before `dead_t`, `(sample[k] - sample[k-1]) / dt`. Walks
## back past any STALLED pair rather than reading the first one it finds —
## [method BladeState.remove_vertex] zeroes the dead vertex's `inv_mass`, so
## every sample from `dead_at` onward is identical to the last, and diffing
## that pair would read zero momentum for a vertex that was very much moving
## right up to the moment it died. Zero at `t = 0` (nothing to diff against
## yet) is the owner's accepted floor, not a bug. Never [member
## BladeTrajectory.prev_samples] — that is a mid-SUBSTEP pose, not one `dt`
## apart from `samples`.
static func seed_velocity(traj: BladeTrajectory, idx: int, dead_t: float) -> Vector2:
	if traj == null or traj.samples.size() < 2 or traj.sample_dt <= 0.0:
		return Vector2.ZERO
	var dt := traj.sample_dt
	var k := mini(int(dead_t / dt), traj.samples.size() - 1)
	while k >= 1:
		var a := traj.samples[k]
		var b := traj.samples[k - 1]
		if idx < a.size() and idx < b.size() \
				and a[idx].distance_squared_to(b[idx]) > 0.0001:
			return (a[idx] - b[idx]) / dt
		k -= 1
	return Vector2.ZERO


## The shard field this blade's pops spawn into (#787) — exposed for
## look-tuning (`addons/melee_sandbox`) and test inspection, same as [method
## get_node_visuals].
func get_shard_field() -> ShatterField:
	return _shard_field


func _speed_multiplier(ev: BladeHitEvent) -> float:
	var board: StatBoard = owned_by.stat_board if owned_by != null else null
	var m := BladeState.stat_value(board, &"blade_speed_multiplier_max", 1.0)
	var v_half := BladeState.stat_value(board, &"blade_speed_half", 0.0)
	return BladeState.speed_damage_multiplier(ev.speed, m, v_half)


## Stop any in-flight playback. Emits playback_finished so awaiters wake up.
func stop() -> void:
	_finish_form()
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null
		playback_finished.emit()


## Stage the committed swing's WIND-UP (#559) and return the seconds it
## occupies. [b]Never awaited by anyone[/b] — this starts a Tween and returns
## immediately; [BattleSystem] waits out the returned length on its own beat
## clock, so a dropped frame or a killed tween cannot move when the swing
## begins (`.claude/rules/presentation-clock.md`).
##
## The sequence, owner-authored (#559 decision 4):
## [codeblock]
## (pivot focus, the camera's beat) -> vertices form in, staggered by hop
## distance from the pivot -> addon stamps land on the vertices that carry one
## -> the whole blade ramps up in glow -> a flare marks the replay start
## [/codeblock]
##
## [b]Vertices spawn under-lit, not translucent.[/b] Alpha is the fade channel
## and colour VALUE is the dimmer (`.claude/rules/hdr-color.md`), so the
## appear-in rides `modulate:a` + `scale` while the glow ramp rides the rgb
## channels back up to 1.0 — the authored [BladeStyle] tiers are never
## re-picked, they are only dimmed and restored. The flare is a momentary
## overshoot to [constant Emissive.PEAK] on the blade's own `modulate`, which
## is precisely what that tier is reserved for.
##
## [param lead] delays the whole sequence, covering the camera's pivot beat.
## [param stamp_time] is spent only when some vertex actually carries an addon.
## Every duration is authored on [PresentationTempo]; passing 0.0 for all five
## reproduces pre-#559 behaviour exactly (the blade is simply there).
func form_in(lead: float, stagger_span: float, stamp_time: float,
		glow_ramp: float, flare_time: float) -> float:
	_finish_form()
	if _node_visuals.is_empty():
		return 0.0
	lead = maxf(0.0, lead)
	stagger_span = maxf(0.0, stagger_span)
	glow_ramp = maxf(0.0, glow_ramp)
	flare_time = maxf(0.0, flare_time)
	var stamped := _stamped_vertices()
	var stamp := maxf(0.0, stamp_time) if not stamped.is_empty() else 0.0
	var total := lead + stagger_span + stamp + glow_ramp + flare_time
	if total <= 0.0:
		form_instantly()
		return 0.0

	var hops := _hop_distances()
	var max_hop: int = 0
	for h in hops:
		max_hop = maxi(max_hop, h)
	# Each vertex's own pop is a fraction of the span, floored so a one-hop
	# blade still reads as an animation rather than a cut.
	var pop := maxf(0.06, stagger_span * 0.5)

	var tween := create_tween()
	tween.set_parallel(true)
	_form_tween = tween
	var glow_at := lead + stagger_span + stamp

	for i in _node_visuals.size():
		var bn := _node_visuals[i]
		var at: float = lead
		if max_hop > 0:
			at += stagger_span * (float(hops[i]) / float(max_hop))
		# Set the start state NOW: a Tween delay does not pre-apply it, so
		# without this the whole blade flashes at full for one frame.
		bn.modulate = Color(_FORM_DIM, _FORM_DIM, _FORM_DIM, 0.0)
		bn.scale = Vector2(_FORM_SCALE, _FORM_SCALE)
		tween.tween_property(bn, "modulate:a", 1.0, pop).set_delay(at)
		tween.tween_property(bn, "scale", Vector2.ONE, pop).set_delay(at) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if stamp > 0.0 and stamped.has(i):
			# The stamp: a punch on the same property, strictly after the form
			# tweener has finished writing it. Parallel tweeners with disjoint
			# delay windows hand the property off cleanly.
			var stamp_at := lead + stagger_span
			if max_hop > 0:
				stamp_at = lead + stagger_span + stamp * (float(hops[i]) / float(max_hop)) * 0.5
			tween.tween_property(bn, "scale", Vector2.ONE * _STAMP_SCALE, stamp * 0.4) \
					.set_delay(stamp_at)
			tween.tween_property(bn, "scale", Vector2.ONE, stamp * 0.6) \
					.set_delay(stamp_at + stamp * 0.4)
		for channel in ["modulate:r", "modulate:g", "modulate:b"]:
			tween.tween_property(bn, channel, 1.0, glow_ramp).set_delay(glow_at)

	for j in _edge_visuals.size():
		var be := _edge_visuals[j]
		var e: Vector2i = state.edges[j]
		var at_e: float = lead
		if max_hop > 0:
			at_e += stagger_span * (float(maxi(hops[e.x], hops[e.y])) / float(max_hop))
		be.modulate = Color(_FORM_DIM, _FORM_DIM, _FORM_DIM, 0.0)
		tween.tween_property(be, "modulate:a", 1.0, pop).set_delay(at_e)
		for channel in ["modulate:r", "modulate:g", "modulate:b"]:
			tween.tween_property(be, channel, 1.0, glow_ramp).set_delay(glow_at)

	if flare_time > 0.0:
		var flare := Emissive.at(Color.WHITE, Emissive.PEAK)
		flare.a = modulate.a
		tween.tween_property(self, "modulate", flare, flare_time * 0.35) \
				.set_delay(glow_at + glow_ramp)
		tween.tween_property(self, "modulate", Color.WHITE, flare_time * 0.65) \
				.set_delay(glow_at + glow_ramp + flare_time * 0.35)
	return total


## The zero-length wind-up: every beat authored (or gated) to 0, so the blade
## is simply there, fully formed and fully lit. This is what a SEATED actor
## gets — #559's sharpening on decision 1 is that the sequence still RUNS for
## every actor, and only its durations collapse, so the await point #796 needs
## survives on the one machine that most needs it.
func form_instantly() -> void:
	_finish_form()


## Kill any in-flight wind-up and snap every visual to its settled state.
## Idempotent, and safe on a blade that never formed — the settled state is
## exactly what [method _spawn_visuals] leaves behind.
func _finish_form() -> void:
	if _form_tween != null and _form_tween.is_valid():
		_form_tween.kill()
	_form_tween = null
	for bn in _node_visuals:
		bn.modulate = Color.WHITE
		bn.scale = Vector2.ONE
	for be in _edge_visuals:
		be.modulate = Color.WHITE
	modulate.r = 1.0
	modulate.g = 1.0
	modulate.b = 1.0


## Which vertex indices carry at least one addon, so the stamp beat lands on
## them and only them. An unadorned blade returns empty, which is what makes
## the beat zero-length.
func _stamped_vertices() -> Dictionary:
	var out: Dictionary = {}
	for i in _source_nodes.size():
		var sn := _source_nodes[i]
		if sn != null and is_instance_valid(sn) and not sn.get_addons().is_empty():
			out[i] = true
	return out


## Hop distance from the pivot for every vertex, measured INSIDE
## [member BladeState.edges] — the phantom blade's own induced subgraph, braces
## excluded (`.claude/rules/degree.md`; [ClampAddon] contributes to
## `state.constraints`, never to `edges`). A vertex unreachable through those
## edges keeps distance 0 rather than staying unformed.
func _hop_distances() -> PackedInt32Array:
	var n := _node_visuals.size()
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(0)
	if state == null or n == 0:
		return out
	var adj: Array[PackedInt32Array] = []
	adj.resize(n)
	for i in n:
		adj[i] = PackedInt32Array()
	for e in state.edges:
		if e.x < n and e.y < n:
			adj[e.x].append(e.y)
			adj[e.y].append(e.x)
	var seen := {}
	var frontier := PackedInt32Array([state.pivot_index])
	seen[state.pivot_index] = true
	var depth := 0
	while not frontier.is_empty():
		var next := PackedInt32Array()
		for v in frontier:
			out[v] = depth
			for w in adj[v]:
				if not seen.has(w):
					seen[w] = true
					next.append(w)
		frontier = next
		depth += 1
	return out


func _build_swing_drivers(duration: float) -> Array[BladeDriver]:
	var drivers: Array[BladeDriver] = []
	var pivot_pos := state.positions[state.pivot_index]
	var seen: Dictionary = {}
	var sweep := -TAU if swing_cw else TAU
	for e in state.edges:
		var other := -1
		if e.x == state.pivot_index:
			other = e.y
		elif e.y == state.pivot_index:
			other = e.x
		if other < 0 or seen.has(other):
			continue
		seen[other] = true
		var offset := state.positions[other] - pivot_pos
		drivers.append(BladeArcDriver.new(
				other, pivot_pos, offset.length(), offset.angle(),
				sweep, duration))
	return drivers


func _clear_visuals() -> void:
	for n in _node_visuals:
		n.queue_free()
	for e in _edge_visuals:
		e.queue_free()
	_node_visuals.clear()
	_edge_visuals.clear()


func _spawn_visuals() -> void:
	var tint := entity_tint()
	for i in state.positions.size():
		var bn := BLADE_NODE.instantiate() as BladeNode
		bn.radius = state.radii[i]
		bn.inner_radius = state.inner_radii[i]
		bn.is_pivot = (i == state.pivot_index)
		bn.style = style
		bn.tint = tint
		_nodes_container.add_child(bn)
		bn.global_position = state.positions[i]
		_node_visuals.append(bn)
	for e in state.edges:
		var be := BLADE_EDGE.instantiate() as BladeEdge
		be.style = style
		be.tint = tint
		_edges_container.add_child(be)
		be.from = _node_visuals[e.x]
		be.to = _node_visuals[e.y]
		_edge_visuals.append(be)


## The wielder's identity colour, or transparent when the blade has no owner
## (headless fixtures) — [BladeStyle] reads that as "authored base only".
func entity_tint() -> Color:
	return owned_by.color if owned_by != null else Color.TRANSPARENT


## Re-push the style (and the tint that rides with it) onto live visuals, so a
## sandbox swapping the resource mid-swing repaints without a rebuild.
func _apply_style() -> void:
	var tint := entity_tint()
	for bn in _node_visuals:
		bn.style = style
		bn.tint = tint
	for be in _edge_visuals:
		be.style = style
		be.tint = tint
	_push_shard_look()


## Pushes the two [BladeStyle] knobs the shard shader CAN read off this
## blade's own [BladeStyle] onto [member _shard_field]'s material — fill
## alpha and the rim-over-fill EV lift, mirroring [method BladeCircle._draw]'s
## own fill_color/rim_color split. `inner_frac` stays a fixed material default
## (see `blade_shard.gdshader`'s own comment): it is a per-SOURCE-NODE ratio,
## and there is no spare per-shard channel to carry it.
func _push_shard_look() -> void:
	if _shard_field == null:
		return
	var mat := _shard_field.material as ShaderMaterial
	if mat == null:
		return
	var s: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
	mat.set_shader_parameter(&"fill_alpha", s.fill_alpha)
	mat.set_shader_parameter(&"rim_lift_stops", maxf(s.rim_tier - s.fill_tier, 0.0))


## The spawned vertex visuals, pivot included, in [BladeState] particle order —
## so the sandbox can force a vertex de-lit for look tuning without inventing a
## fake [BladePopResolver.Result].
func get_node_visuals() -> Array[BladeNode]:
	return _node_visuals


## The spawned edge visuals, in [member BladeState.edges] order — the edge
## counterpart of [method get_node_visuals], for the same look-tuning /
## test-inspection use (#781's bunker break de-lights one of these).
func get_edge_visuals() -> Array[BladeEdge]:
	return _edge_visuals
