extends GutTest

## #797: where the ~2.4 s of an AI turn on a 4-node graph actually goes.
##
## Run: [code]mise run test:one -- res://test/perf/bench_ai_turn.gd[/code]
##
## [b]Not collected by the suite[/b] — same double opt-out as its siblings in
## `test/perf/`: outside `.gutconfig.json`'s `test/unit/`, and the `bench_`
## prefix keeps even `test:dir` from finding it.
##
## [b]The fixture is the issue's fixture[/b] — a byte-for-byte rebuild of
## `test/unit/scenes/test_game_root_link_loss.gd`'s `before_each` (a real
## [GameRoot], 4 SkillNodes in a path, two entities on the ends, host roster,
## `ai_turn_delay = 0.0`), so the total this file reports is comparable to the
## 2370 ms recorded on #797 and not to some other board.
##
## [b]How it decomposes without touching production code[/b]: [ProbeAI] is an
## [AIController] subclass that overrides the gather / allocate / execute /
## wait hooks with a stopwatch and calls `super()`. So the TURN is the real
## turn — the same coroutine, the same commands, the same applier. The one
## exception is `_gather_melee_candidates`, which re-sequences
## [AiBladeRollout]'s own private statics rather than calling the public
## entry point; that is a sequencing copy, not a logic copy (every stage is
## still the shipped function), and
## `test_the_decomposition_agrees_with_the_real_rollout` pins the two to the
## same finalists so a drift in either is a red test, not a silently wrong
## table.
##
## [b]Both backends in one run.[/b] `BladeSim.use_native` is a plain static
## bool, so a single process can measure native and GDScript back to back on
## two identical fresh fixtures. The whole point of the exercise is what #798
## bought on THIS path; a table with one column cannot say.
##
## Numbers move with the machine — record the CPU alongside any result.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

const _HOST_PEER := 1
const _REMOTE_PEER := 2

## Repetitions for the per-resolve micro-split. The split re-runs a finalist's
## `resolve()` and its individual stages against the board as the turn left it;
## the AI takes no action on this fixture, so that board is the one the last
## gather actually saw.
const _RESOLVE_REPS := 5

var _saved_ai_delay: float
var _saved_use_native: bool


func before_each() -> void:
	GameSession.end()
	_saved_ai_delay = Settings.current.ai_turn_delay
	_saved_use_native = BladeSim.use_native
	Settings.current.ai_turn_delay = 0.0


func after_each() -> void:
	Settings.current.ai_turn_delay = _saved_ai_delay
	BladeSim.use_native = _saved_use_native
	GameSession.end()


# ── the instrumented controller ─────────────────────────────────────────────


## An [AIController] that keeps a stopwatch on every hook the turn passes
## through. Buckets are microseconds, keyed by StringName; `_other` is
## whatever the total is not accounted for by the rest.
class ProbeAI:
	extends AIController

	var buckets: Dictionary = {}
	## `[pivot, Array[SkillNode] members, bool swing_cw]` for the finalists of
	## the LAST melee gather this turn — the input to the resolve micro-split.
	var last_finalists: Array = []
	var melee_gathers: int = 0

	## Wall clock only — for a bucket that cannot await.
	func bump(key: StringName, usec: int) -> void:
		buckets[key] = int(buckets.get(key, 0)) + usec

	## Wall clock AND process frames. A bucket that burned frames was WAITING
	## (a reveal-clock beat, a timer); a bucket at zero frames was computing.
	## #797 asks explicitly not to quote wall time as compute until that is
	## separated, so every awaiting hook records both.
	func bump2(key: StringName, usec: int, frames: int) -> void:
		bump(key, usec)
		buckets[StringName(String(key) + "_frames")] = \
				int(buckets.get(StringName(String(key) + "_frames"), 0)) + frames

	func _gather_ranged_candidates(ve: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
		var t := Time.get_ticks_usec()
		var r := super(ve)
		bump(&"ranged", Time.get_ticks_usec() - t)
		return r

	func _gather_magic_candidates(ve: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
		var t := Time.get_ticks_usec()
		var r := super(ve)
		bump(&"magic", Time.get_ticks_usec() - t)
		return r

	## The one override that does NOT call `super()` — see the class doc.
	## Re-sequences [AiBladeRollout]'s own statics so the melee bucket splits
	## into prep / coarse / finalist-resolve instead of arriving as one number.
	func _gather_melee_candidates(ve: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
		var t_all := Time.get_ticks_usec()
		var out := ProbeAI.gather_melee_decomposed(entity, ve, ai_tier, self)
		bump(&"melee_total", Time.get_ticks_usec() - t_all)
		melee_gathers += 1
		return out

	func _try_allocate_frontier(ve: Array[SkillNode]) -> bool:
		var t := Time.get_ticks_usec()
		var f := Engine.get_process_frames()
		var r := await super(ve)
		bump2(&"allocate", Time.get_ticks_usec() - t, int(Engine.get_process_frames() - f))
		return r

	func _execute_candidate(c: AiCombatScorer.ScoredCandidate) -> bool:
		var t := Time.get_ticks_usec()
		var f := Engine.get_process_frames()
		var r := await super(c)
		bump2(&"execute", Time.get_ticks_usec() - t, int(Engine.get_process_frames() - f))
		return r

	func _wait() -> void:
		var t := Time.get_ticks_usec()
		var f := Engine.get_process_frames()
		await super()
		bump2(&"wait", Time.get_ticks_usec() - t, int(Engine.get_process_frames() - f))


	## [method AiBladeRollout.gather_melee_candidates]'s body, stage by stage,
	## every stage still the shipped static. `probe` may be null (the agreement
	## test calls it that way to get the result without recording anything).
	static func gather_melee_decomposed(
			entity: Entity, visible_enemies: Array[SkillNode], ai_tier: int, probe: ProbeAI
	) -> Array[AiCombatScorer.ScoredCandidate]:
		var out: Array[AiCombatScorer.ScoredCandidate] = []
		if entity == null or entity.navigator == null or visible_enemies.is_empty():
			return out

		var t := Time.get_ticks_usec()
		var adjacency := AiBladeRollout._owned_adjacency(entity)
		if adjacency.is_empty():
			return out
		var enemy_positions: Array[Vector2] = []
		for e in visible_enemies:
			if e != null:
				enemy_positions.append(e.global_position)
		if enemy_positions.is_empty():
			return out
		var target_centroid := Vector2.ZERO
		for p in enemy_positions:
			target_centroid += p
		target_centroid /= enemy_positions.size()
		var pivot_infos := AiBladeRollout._prune_pivots(adjacency, enemy_positions)
		if pivot_infos.is_empty():
			return out
		var proposals := AiBladeRollout._propose_blade_selections(
				pivot_infos, adjacency, target_centroid)
		if probe != null:
			probe.bump(&"melee_prep", Time.get_ticks_usec() - t)
			probe.bump(&"n_proposals", proposals.size())
		if proposals.is_empty():
			return out

		t = Time.get_ticks_usec()
		var finalists := AiBladeRollout._coarse_rank_and_select(proposals, entity, enemy_positions)
		if probe != null:
			probe.bump(&"melee_coarse", Time.get_ticks_usec() - t)
			probe.last_finalists = finalists.duplicate()

		t = Time.get_ticks_usec()
		for f in finalists:
			var candidate := AiBladeRollout._resolve_and_score(
					entity, f[0], f[1], f[2], visible_enemies, ai_tier)
			if candidate != null:
				out.append(candidate)
		if probe != null:
			probe.bump(&"melee_finalists", Time.get_ticks_usec() - t)
			probe.bump(&"n_finalists", finalists.size())
		return out


# ── fixture ─────────────────────────────────────────────────────────────────


## #797's fixture verbatim. Returns
## `{root, local, remote}`; the caller drives `remote` with a [ProbeAI].
func _build_fixture() -> Dictionary:
	GameSession.network = NetworkConfig.host()
	GameSession.local_peer_id = _HOST_PEER

	var root: GameRoot = _GAME_ROOT.instantiate()
	root.auto_start_turn = false
	root.route_to_meta_on_run_end = false
	add_child_autofree(root)
	await wait_frames(6)

	var nodes: Array[SkillNode] = []
	for i in 4:
		var sn := _SKILL_NODE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 120, 0)
		root.graph.add_skill_node(sn)
		nodes.append(sn)
	for i in 3:
		root.graph.add_edge(nodes[i], nodes[i + 1])

	var local := root.spawn_entity("Host", Color.CYAN, nodes[0], _BALANCED)
	var remote := root.spawn_entity("Guest", Color.ORANGE, nodes[3], _BALANCED)

	var roster := ParticipantRoster.new()
	var host_seat := Participant.new()
	host_seat.id = 1
	host_seat.kind = Participant.Kind.HUMAN
	host_seat.camp = _CAMP_1
	host_seat.peer_id = _HOST_PEER
	roster.add(host_seat)
	var remote_seat := Participant.new()
	remote_seat.id = 2
	remote_seat.kind = Participant.Kind.HUMAN
	remote_seat.camp = _CAMP_2
	remote_seat.peer_id = _REMOTE_PEER
	roster.add(remote_seat)
	GameSession.roster = roster
	GameRoot.apply_roster({1: local, 2: remote}, roster)
	root._ensure_controllers()
	root.bind_player(local)
	await wait_frames(1)
	return {"root": root, "local": local, "remote": remote, "seat": remote_seat}


## Swap `remote`'s controller for a [ProbeAI] — the same swap
## [method GameRoot.hand_seat_to_ai] performs, minus the transport event, so
## the bench is not also measuring the handover.
func _install_probe(root: GameRoot, ent: Entity) -> ProbeAI:
	var old := GameRoot._find_controller(ent)
	if old != null:
		ent.remove_child(old)
		old.queue_free()
	var probe := ProbeAI.new()
	probe.name = "AIController"
	probe.turn_delay = 0.0
	ent.add_child(probe)
	ent.is_human_controlled = false
	await wait_frames(1)
	return probe


# ── the measurement ─────────────────────────────────────────────────────────


func _ms(probe: ProbeAI, key: StringName) -> float:
	return float(int(probe.buckets.get(key, 0))) / 1000.0


## One full turn under one backend. Returns the probe plus the wall clock.
func _run_turn(label: String, use_native: bool) -> Dictionary:
	BladeSim.use_native = use_native
	var fx := await _build_fixture()
	var root: GameRoot = fx["root"]
	var remote: Entity = fx["remote"]
	var probe := await _install_probe(root, remote)

	# `start_turn` emits `turn_started`, which [EntityController] already
	# dispatches to `take_turn()` — calling it by hand as well runs the whole
	# turn TWICE, concurrently, which reads as buckets summing past 100%.
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	root.turn_manager.start_turn(remote)
	await wait_for_signal(root.turn_manager.turn_ended, 60.0)
	var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var total_frames := int(Engine.get_process_frames() - f0)

	gut.p("")
	gut.p("=== %s (backend: %s) ===" % [label, BladeSim.backend()])
	gut.p("  TOTAL turn wall clock          : %8.1f ms over %d frames" % [total_ms, total_frames])
	var named := 0.0
	for key in [&"allocate", &"ranged", &"magic", &"melee_total", &"execute", &"wait"]:
		named += _ms(probe, key)
	for key in [&"allocate", &"ranged", &"magic", &"melee_total", &"execute", &"wait"]:
		gut.p("    %-28s : %8.1f ms  (%5.1f%%)  %d frame(s)"
				% [key, _ms(probe, key), 100.0 * _ms(probe, key) / maxf(total_ms, 0.001),
					int(probe.buckets.get(StringName(String(key) + "_frames"), 0))])
	gut.p("    %-28s : %8.1f ms  (%5.1f%%)"
			% ["recon + loop bookkeeping", total_ms - named,
				100.0 * (total_ms - named) / maxf(total_ms, 0.001)])
	# The headline #797 asks for: wall time is not compute. A bucket that
	# burned process frames was parked on the presentation clock while the
	# engine idled (headless GUT runs ~140 fps here, so a frame is ~7 ms of
	# REAL time, not of work) — only the zero-frame buckets are deliberation.
	var deliberation := _ms(probe, &"ranged") + _ms(probe, &"magic") + _ms(probe, &"melee_total")
	gut.p("  --> DELIBERATION (zero-frame, i.e. real compute): %.1f ms  (%.2f%% of the turn)"
			% [deliberation, 100.0 * deliberation / maxf(total_ms, 0.001)])
	gut.p("  --> everything else is frame-paced presentation: %d of %d frames sit inside allocate+execute"
			% [int(probe.buckets.get(&"allocate_frames", 0)) + int(probe.buckets.get(&"execute_frames", 0)),
				total_frames])
	gut.p("  melee split (%d gather(s), %d proposals, %d finalists per gather):"
			% [probe.melee_gathers, int(probe.buckets.get(&"n_proposals", 0)),
				int(probe.buckets.get(&"n_finalists", 0))])
	for key in [&"melee_prep", &"melee_coarse", &"melee_finalists"]:
		gut.p("    %-28s : %8.1f ms  (%5.1f%% of turn)"
				% [key, _ms(probe, key), 100.0 * _ms(probe, key) / maxf(total_ms, 0.001)])

	await _resolve_micro_split(probe, remote)

	assert_gt(total_ms, 0.0, "the turn must have taken measurable time")
	return {"probe": probe, "total_ms": total_ms, "root": root, "remote": remote}


## Split ONE finalist's `plan.resolve()` into its stages. The AI takes no
## action on this fixture (it submits `end_turn` only — #797), so the board
## here is the board the last gather saw.
func _resolve_micro_split(probe: ProbeAI, ent: Entity) -> void:
	if probe.last_finalists.is_empty():
		gut.p("  resolve split: no finalists — nothing to split")
		return
	var f: Array = probe.last_finalists[0]
	var plan := MeleeAttackPlan.new()
	plan.attacker = ent
	plan.source = f[0]
	plan.blade_nodes = f[1]
	plan.swing_cw = f[2]
	if not plan.is_valid():
		gut.p("  resolve split: the captured finalist no longer validates")
		return

	var t := Time.get_ticks_usec()
	for _r in _RESOLVE_REPS:
		var w := CombatWorld.shadow()
		w.free_shadow()
	var shadow_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	t = Time.get_ticks_usec()
	var state: BladeState = null
	for _r in _RESOLVE_REPS:
		state = plan.build_blade_state()
	var state_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	t = Time.get_ticks_usec()
	var drivers: Array[BladeDriver] = []
	for _r in _RESOLVE_REPS:
		drivers = plan.build_drivers(state)
	var drivers_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	t = Time.get_ticks_usec()
	var traj: BladeTrajectory = null
	for _r in _RESOLVE_REPS:
		traj = BladeSim.simulate(state, drivers, MeleeAttackPlan.SWING_DURATION)
	var sim_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	var space := plan.source.get_world_2d().direct_space_state
	var exclude := plan.collect_target_excludes()
	t = Time.get_ticks_usec()
	var events: Array[BladeHitEvent] = []
	for _r in _RESOLVE_REPS:
		events = BladeHitScan.scan(
				traj, state, space, ent.navigator.graph, 0xFFFFFFFF, exclude)
	var scan_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	t = Time.get_ticks_usec()
	for _r in _RESOLVE_REPS:
		BladePopResolver.LiveGate.new(state, ent)
	var gate_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	t = Time.get_ticks_usec()
	for _r in _RESOLVE_REPS:
		plan.resolve()
	var full_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	# The coarse tier's own per-call cost, for the two-tier question (#797 Q1).
	t = Time.get_ticks_usec()
	for _r in _RESOLVE_REPS:
		BladeSim.simulate(state, drivers, MeleeAttackPlan.SWING_DURATION,
				AiBladeRollout._COARSE_DT, AiBladeRollout._COARSE_ITERS)
	var coarse_ms := float(Time.get_ticks_usec() - t) / float(_RESOLVE_REPS) / 1000.0

	gut.p("  ONE finalist resolve, split (%d vertices / %d edges, %d substeps, %d events):"
			% [state.positions.size(), state.edges.size(), traj.samples.size(), events.size()])
	gut.p("    %-28s : %8.3f ms" % ["CombatWorld.shadow()+free", shadow_ms])
	gut.p("    %-28s : %8.3f ms" % ["build_blade_state", state_ms])
	gut.p("    %-28s : %8.3f ms" % ["build_drivers", drivers_ms])
	gut.p("    %-28s : %8.3f ms" % ["BladeSim.simulate (full)", sim_ms])
	gut.p("    %-28s : %8.3f ms" % ["BladeHitScan.scan", scan_ms])
	gut.p("    %-28s : %8.3f ms" % ["plan.resolve() WHOLE", full_ms])
	gut.p("    %-28s : %8.3f ms" % ["LiveGate.new", gate_ms])
	# Whatever `resolve_against` costs on top of the stages above: the
	# DamageInstance loop, OutcomeSchedule.compile, CritRoll.decide_all and
	# OutcomeApplier.apply (which is where BladeDamageInstance.land_on and its
	# StatBoard reads live — #797's third named suspect).
	gut.p("    %-28s : %8.3f ms" % ["  ...remainder (build+apply)",
			full_ms - shadow_ms - state_ms - drivers_ms - sim_ms - scan_ms - gate_ms])
	gut.p("    %-28s : %8.3f ms" % ["BladeSim.simulate (COARSE)", coarse_ms])
	gut.p("    %-28s : %8.2fx" % ["full / coarse", sim_ms / maxf(coarse_ms, 0.00001)])


func test_bench_ai_turn_native_backend() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — build with `mise run native:build`, then `mise run refresh`")
		return
	await _run_turn("AI turn on #797's 4-node fixture", true)


func test_bench_ai_turn_gdscript_backend() -> void:
	await _run_turn("AI turn on #797's 4-node fixture", false)


## The decomposition is a re-sequencing of [AiBladeRollout]'s statics, not a
## second implementation — this pins that. If the public entry point grows a
## stage the table above does not price, the finalist sets diverge and this
## goes red rather than the numbers going quietly wrong.
func test_the_decomposition_agrees_with_the_real_rollout() -> void:
	var fx := await _build_fixture()
	var remote: Entity = fx["remote"]
	# Give the AI something to swing at: the fixture starts with one node
	# each, so grow the guest one hop toward the host.
	var enemies := AiRecon.visible_enemy_nodes(remote)
	var real := AiBladeRollout.gather_melee_candidates(remote, enemies, 0)
	var mine := ProbeAI.gather_melee_decomposed(remote, enemies, 0, null)
	assert_eq(mine.size(), real.size(), "same candidate count")
	for i in mini(mine.size(), real.size()):
		assert_eq(mine[i].source_node, real[i].source_node, "same pivot at %d" % i)
		assert_eq(mine[i].swing_cw, real[i].swing_cw, "same direction at %d" % i)
		assert_almost_eq(mine[i].score, real[i].score, 0.0001, "same score at %d" % i)
