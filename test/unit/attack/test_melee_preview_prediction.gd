extends GutTest

## #782 — the aim-time preview PREDICTS what the defenders will do to the swing.
##
## The claim under test is not "the ghost looks similar". It is that the ghost
## IS one real resolve, run against a throwaway [CombatWorld] shadow, replayed:
## same trajectory, same pops, same edge severances, same drag clock. So most of
## these tests are equalities against [method MeleeAttackPlan.resolve_against]
## rather than hand-written expectations — a predictor that merely agreed with a
## rule would be the parallel mirror #782 exists to avoid.
##
## Fixtures follow `test_severed_swing_live.gd` (spike) and
## `test_bunker_break_live.gd` (bunker) — real graph, real allocation, real
## physics-backed defenders, since the pop gate and the hit scan both read them.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")
const _FORT_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")

const _SPACING := 150.0
## Fraction of a full turn round the tip's own arc where a defender sits —
## `test_bunker_break_live.gd`'s convention, far enough in that the contact
## happens well after the swing starts.
const _TURNS := 0.15

## Particle indices into the blade state: `build_blade_state` builds
## `[source] + blade_nodes`, and the fixture selects pivot, mid, tip.
const _MID_IDX := 1
const _TIP_IDX := 2

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _blocker: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## A fixed spikes cap, bypassing SpikeRingAddon's stake-scaled curve — the same
## technique `test_spike_pop_budget.gd` and `test_severed_swing_live.gd` use.
func _set_spikes_cap(node: SkillNode, cap: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spikes"
	mod.operation = StatModifier.Operation.SET
	mod.value = cap
	node.add_local_modifier(mod)


func _make_entity() -> Entity:
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# No crits anywhere in this file: the preview runs on the unstamped (0)
	# stream and the committed swing on a fresh one, and the ONE way those two
	# can disagree is a crit-driven kill changing a later defender's board
	# mid-swing (see `MeleeAttackPlan.refresh_prediction`). Zeroing the chance
	# removes that seam so the equalities below test the prediction path itself.
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


## The shared world: a pivot-mid-tip spine owned by the attacker, plus one
## hostile `blocker` node whose defensive character each test authors itself.
## `blocker_pos` places it; the caller attaches the addon it wants.
func _setup(blocker_pos: Vector2) -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_preview = MeleePreview.new()
	add_child_autofree(_preview)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.melee_preview = _preview
	_preview.battle_system = _bs
	add_child(_bs)
	_preview._ready()

	_attacker = _make_entity()
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_tm.current_entity = _attacker

	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"melee_preview_prediction_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_blocker = _spawn("Blocker", blocker_pos)

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _blocker)
	_defender.core_location = _blocker

	# The wielder's baseline blade_damage is 0 with no CoreClass assigned, so
	# without this every contact lands for exactly 0 — see the same gap noted in
	# test_severed_swing_live.gd.
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 20.0
	_tip.add_local_modifier(sharp)
	_mid.add_local_modifier(sharp.duplicate() as StatModifier)


## Ready the fixture for a swing: two physics frames so the defenders' bodies
## exist for the hit scan, then a fresh selection through the real click path.
func _arm() -> MeleeAttackPlan:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_bs.request_attack_mode(BattleSystem.AttackMode.NONE)
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_mid)
	plan._on_node_left_clicked(_tip)
	assert_true(plan.is_valid(), "fixture: the plan must be valid before resolving")
	return plan


## A fresh plan over the same selection, so a prediction can be compared against
## a resolve that has not been influenced by it. Deliberately NOT the same
## instance: `resolve_against` mutates the real world through the live
## CombatWorld, which would change what a second run sees.
func _twin_plan() -> MeleeAttackPlan:
	var twin := MeleeAttackPlan.new()
	twin.attacker = _attacker
	twin.source = _pivot
	twin.blade_nodes = [_mid, _tip]
	return twin


# ── acceptance 1: the popped vertex is ghosted, its popper is marked ─────────

## The spiked case. `_blocker` sits a fifth of a turn round the MID vertex's own
## orbit, with exactly one spike — so the mid vertex is destroyed partway
## through the swing and the tip is severed behind it.
func test_a_spike_pop_is_predicted_and_its_defender_is_marked() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()

	plan.refresh_prediction()
	var prediction := plan.prediction()
	assert_not_null(prediction, "an armed valid selection must have a prediction")
	assert_eq(prediction.pops.vertex_pop_count(), 1,
			"the spiked node pops exactly one vertex")
	var pop: BladePopResolver.Pop = prediction.pops.pops[0]
	assert_eq(pop.particle_idx, _MID_IDX, "the mid vertex is the one that dies")
	assert_eq(pop.defender, _blocker, "the pop names the node that did it")

	# What dies: the ghost de-lits it, and does so AT the pop time rather than
	# pre-greying it, so the player watches the spike take it.
	assert_false(prediction.pops.is_dead(_MID_IDX, 0.0),
			"before the pop the vertex is alive — the ghosting is on the swing's clock")
	assert_true(prediction.pops.is_dead(_MID_IDX, pop.t),
			"from its pop time on, the vertex reads dead")

	# What does it: the defender is marked for the overlay, before any commit.
	assert_eq(plan.get_node_role(_blocker),
			HighlightProvider.HighlightRole.PREDICTED_THREAT,
			"the popping defender is marked PREDICTED_THREAT")
	assert_eq(plan.get_node_role(_tip), HighlightProvider.HighlightRole.MEMBER,
			"a blade member keeps its own role")


## The ghost actually receives the prediction — the loop assigns `pop_result`
## before its first await, so this is readable synchronously off the mounted
## blade. Without it the vertices would never go dark on screen.
func test_the_mounted_ghost_replays_the_predicted_pops() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()

	var blade := _preview.current_blade()
	assert_not_null(blade, "a valid selection mounts a ghost")
	# `prediction_partial` rather than `prediction` since #821: a click buys one
	# SLICE, so the completed cache is still empty here. Both accessors return
	# the same bundle — the run publishes `pops` and `obstacles` before its first
	# step precisely so a half-resolved swing still draws.
	assert_same(blade.pop_result, plan.prediction_partial().pops,
			"the ghost replays the prediction's own pop result, not a copy")
	assert_same(blade.state.obstacles, plan.prediction_partial().obstacles,
			"and the predicted swing's own obstacle field, for the strain readout")


# ── acceptance 2: a bunker shatter is predicted ──────────────────────────────

## A rigid spine (Clamp on `mid`) driven into a bunker breaks the mid-tip edge
## rather than popping a vertex (ADR 0005). The preview must show that.
func test_a_bunker_shatter_is_predicted_and_its_defender_is_marked() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * (_SPACING * 2.0))
	_mid.add_child(_CLAMP_SCENE.instantiate() as SkillNodeAddon)
	_blocker.add_child(_BUNKER_SCENE.instantiate() as SkillNodeAddon)
	var plan := await _arm()

	plan.refresh_prediction()
	var prediction := plan.prediction()
	assert_not_null(prediction.obstacles,
			"a bunker in reach gives the predicted swing a real obstacle field")
	assert_eq(prediction.pops.vertex_pop_count(), 0,
			"a bunker never pops a vertex (ADR 0005)")
	assert_eq(prediction.pops.severed_at.size(), 1,
			"the rigid spine loses exactly one edge to the plate")
	assert_eq(plan.get_node_role(_blocker),
			HighlightProvider.HighlightRole.PREDICTED_THREAT,
			"the shattering bunker is marked too — one role covers both effects")

	# And it is the SAME break the authority will land.
	var world := CombatWorld.shadow()
	var twin := _twin_plan()
	twin.resolve_against(world)
	world.free_shadow()
	assert_eq(prediction.pops.severed_at.keys(), twin.last_pops.severed_at.keys(),
			"the previewed shatter is the resolved shatter")


# ── acceptance 3: the previewed ARC is the resolved arc, stall included ──────

## The blocker sits on the MID vertex's own orbit — the sole DRIVEN particle,
## which is the only one that tracks its nominal radius. A floppy tip curls
## sharply inward and would sail past a plate placed on its nominal arc (the
## same trap `test_bunker_break_live.gd` documents for its floppy fixture).
func test_fortification_drag_shows_in_the_previewed_arc() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_blocker.add_child(_FORT_SCENE.instantiate() as SkillNodeAddon)
	var plan := await _arm()

	plan.refresh_prediction()
	var prediction := plan.prediction()
	assert_not_null(prediction.clock,
			"a fortified node in reach gives the predicted swing a drag clock")
	assert_gt(prediction.clock.drag, 0.0,
			"the previewed swing is actually dragged, not merely clocked")

	# Acceptance 3 proper: the previewed ARC is the resolved arc. The drag is in
	# the trajectory, not merely on a clock beside it, so a dragged preview and
	# an undragged resolve would part company here.
	var world := CombatWorld.shadow()
	var twin := _twin_plan()
	twin.resolve_against(world)
	world.free_shadow()
	assert_eq(prediction.trajectory.samples.size(),
			twin.last_trajectory.samples.size(), "same number of samples")
	for i in prediction.trajectory.samples.size():
		assert_eq(prediction.trajectory.samples[i], twin.last_trajectory.samples[i],
				"dragged sample %d must be identical" % i)


# ── acceptance 4: the prediction IS the resolve ──────────────────────────────

## The whole design in one assertion: the preview's trajectory, pops and
## severances are those of a real resolve of the same selection, sample for
## sample — including #801's re-bake from a severance, which no re-simulation of
## an unsevered blade could reproduce.
func test_the_prediction_matches_the_authoritative_resolve_exactly() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()

	plan.refresh_prediction()
	var predicted := plan.prediction()

	var world := CombatWorld.shadow()
	var twin := _twin_plan()
	twin.resolve_against(world)
	world.free_shadow()

	assert_eq(predicted.trajectory.samples.size(), twin.last_trajectory.samples.size(),
			"same number of samples")
	for i in predicted.trajectory.samples.size():
		assert_eq(predicted.trajectory.samples[i], twin.last_trajectory.samples[i],
				"sample %d must be identical" % i)
	assert_eq(predicted.pops.pops.size(), twin.last_pops.pops.size(),
			"same number of pops")
	for i in predicted.pops.pops.size():
		var a: BladePopResolver.Pop = predicted.pops.pops[i]
		var b: BladePopResolver.Pop = twin.last_pops.pops[i]
		assert_eq(a.particle_idx, b.particle_idx, "pop %d hits the same vertex" % i)
		assert_eq(a.t, b.t, "pop %d happens at the same time" % i)
		assert_eq(a.defender, b.defender, "pop %d names the same defender" % i)
	assert_eq(predicted.pops.severed_at.keys(), twin.last_pops.severed_at.keys(),
			"the same edges part")


## The preview resolve must not touch the artifacts the COMMITTED swing replays.
## They are separate by construction now (`_resolve_swing` returns a bundle;
## only `resolve_against` publishes), and this is the regression guard: a
## repaint-driven prediction landing on `last_*` mid-swing would make
## `MeleePreview.launch` animate the wrong swing.
func test_predicting_never_clobbers_the_committed_artifacts() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()

	var world := CombatWorld.shadow()
	plan.resolve_against(world)
	world.free_shadow()
	var committed_traj := plan.last_trajectory
	var committed_pops := plan.last_pops
	assert_not_null(committed_traj, "fixture: the resolve must publish a trajectory")

	plan._invalidate_prediction()
	plan.refresh_prediction()

	assert_same(plan.last_trajectory, committed_traj,
			"the prediction leaves last_trajectory alone")
	assert_same(plan.last_pops, committed_pops,
			"the prediction leaves last_pops alone")
	assert_not_same(plan.prediction().trajectory, committed_traj,
			"and holds a trajectory of its own")


# ── acceptance 5: one resolve per selection, not one per preview cycle ───────

## `refresh_prediction` is the loop's ONLY prediction touch point — it is called
## once per ghost cycle, at the top of `_run_preview_loop` — so N calls stands
## in for N cycles without spending N × 1.2s of wall clock animating them.
func test_the_shadow_resolve_runs_once_per_selection_not_once_per_cycle() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()

	# Arming is three clicks, of which the last two each move a VALID selection —
	# so the mounted preview earns a resolve on each. That is the contract, not
	# an accident: one resolve per selection.
	plan.refresh_prediction()
	var armed := plan.prediction_runs
	assert_gt(armed, 0, "fixture: arming must have resolved at least once")

	for _i in 20:
		plan.refresh_prediction()
	assert_eq(plan.prediction_runs, armed,
			"20 further preview cycles on an unchanged selection resolve nothing")

	# A repaint is not a selection change either: the overlay redraws through
	# BattleSystem's own signal, which must not cost a resolve.
	for _i in 10:
		_bs.attack_plan_state_changed.emit()
	assert_eq(plan.prediction_runs, armed, "repaints are free")


func test_changing_the_selection_earns_a_fresh_resolve() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_set_spikes_cap(_blocker, 1.0)
	var plan := await _arm()
	plan.refresh_prediction()
	var armed := plan.prediction_runs

	# Drop the tip. This goes through the real click path, so it exercises the
	# invalidation every state change shares. The mounted preview re-primes the
	# cache synchronously off the same signal, so assert the COUNT moved rather
	# than that the cache is momentarily empty.
	plan._on_node_left_clicked(_tip)
	plan.refresh_prediction()
	assert_eq(plan.prediction_runs, armed + 1,
			"a changed selection earns exactly one fresh resolve")

	# So does flipping the swing direction — a different arc entirely.
	plan.swing_cw = not plan.swing_cw
	plan.refresh_prediction()
	assert_eq(plan.prediction_runs, armed + 2,
			"the swing direction is an input to the resolve")


# ── #821: the aim-time resolve is time-sliced across frames ─────────────────

## Total trajectory samples in one swing — what a slice run has to reach.
func _swing_steps() -> int:
	return int(ceil(MeleeAttackPlan.SWING_DURATION / BladeSim.DEFAULT_DT))


## Drive a plan's prediction to completion `budget` samples at a time, and
## report how many slices it took.
func _slice_to_completion(plan: MeleeAttackPlan, budget: int) -> int:
	var slices := 0
	while not plan.advance_prediction(budget):
		slices += 1
		assert_lt(slices, _swing_steps() * 4, "the slice loop must terminate")
		if slices > _swing_steps() * 4:
			break
	return slices


## [b]Acceptance 2 — parity is the whole acceptance.[/b] A resolve chopped into
## slices must land on the SAME trajectory, the same pops and the same predicted
## defenders as the single-shot one.
##
## The fixture carries a Fortification, so the swing runs with a real defender
## field and a real drag clock under it. That is the case where a botched stitch
## is SILENT rather than visible: `clock.history`, `obstacles.history` and
## `state.speed_history` are chunk-local by design, and a fresh clock mid-swing
## un-banks the wall's drag and stops it sheltering what is behind it
## (`test_blade_chunked_parity.gd:200-203`). The bit-identity of an arbitrary
## boundary is pinned upstream by
## `test_a_dragged_swing_is_bit_identical_across_a_chunk_boundary`; this is that
## guarantee carried through a whole melee resolve.
func test_a_sliced_prediction_is_identical_to_a_single_shot_one() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	_blocker.add_child(_FORT_SCENE.instantiate() as SkillNodeAddon)
	await _arm()

	var whole_plan := _twin_plan()
	whole_plan.refresh_prediction()
	var whole := whole_plan.prediction()
	assert_not_null(whole, "fixture: the single-shot resolve must produce a swing")
	assert_not_null(whole.obstacles,
			"fixture: a Fortification in reach must give the swing a defender field")
	assert_not_null(whole.clock, "fixture: and its drag clock")

	var sliced_plan := _twin_plan()
	var slices := _slice_to_completion(sliced_plan, 3)
	assert_gt(slices, 3, "fixture: three samples at a time must take many slices")
	var sliced := sliced_plan.prediction()
	assert_not_null(sliced, "the slice run completes")

	assert_eq(sliced.trajectory.samples.size(), whole.trajectory.samples.size(),
			"a sliced swing is the same length as an unsliced one")
	var first_mismatch := -1
	for i in mini(sliced.trajectory.samples.size(), whole.trajectory.samples.size()):
		if sliced.trajectory.samples[i] != whole.trajectory.samples[i]:
			first_mismatch = i
			break
	assert_eq(first_mismatch, -1,
			"every sample is bit-identical — a mismatch at %d means the chunk-local "
			% first_mismatch + "histories were not stitched across a slice boundary")

	assert_eq(sliced.pops.pops.size(), whole.pops.pops.size(),
			"the same vertices pop")
	for i in mini(sliced.pops.pops.size(), whole.pops.pops.size()):
		assert_eq(sliced.pops.pops[i].particle_idx, whole.pops.pops[i].particle_idx,
				"pop %d hits the same vertex" % i)
		assert_eq(sliced.pops.pops[i].t, whole.pops.pops[i].t,
				"pop %d lands at the same time" % i)
		assert_same(sliced.pops.pops[i].defender, whole.pops.pops[i].defender,
				"pop %d names the same defender" % i)
	assert_eq(sliced.pops.severed_at, whole.pops.severed_at,
			"the same edges shatter, at the same times")
	assert_eq(sliced.events.size(), whole.events.size(), "the same contacts land")
	assert_eq(sliced.clock.drag, whole.clock.drag,
			"and the wall banked the same drag — the trap this test exists for")
	assert_eq(sliced.outcome.popped_nodes, whole.outcome.popped_nodes,
			"the AI's shape-risk signal is the same number either way")


## [b]Acceptance 4.[/b] `prediction_runs` counts one logical prediction per
## SELECTION, not one per slice — the same number #782 pinned at 1 across a
## preview loop, unmoved by the resolve now arriving in pieces.
func test_prediction_runs_counts_one_per_selection_not_one_per_slice() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	await _arm()

	var plan := _twin_plan()
	var slices := _slice_to_completion(plan, 2)
	assert_gt(slices, 10, "fixture: two samples at a time must take many slices")
	assert_eq(plan.prediction_runs, 1, "many slices, one logical prediction")

	# And a finished one still costs nothing to ask for again.
	for _i in 20:
		plan.advance_prediction(2)
	assert_eq(plan.prediction_runs, 1, "a warm cache resolves nothing")


## [b]Acceptance-2 decision: a partial trajectory IS a valid picture.[/b] The
## first N steps are readable immediately, off the same bundle the finished run
## publishes, and later ranges EXTEND that bundle rather than replacing it —
## which is what lets the mounted ghost hold a handle on it.
func test_a_partial_run_is_readable_and_extends_in_place() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	await _arm()

	var plan := _twin_plan()
	assert_false(plan.advance_prediction(4), "four samples is not a whole swing")
	assert_true(plan.is_predicting(), "the run is still in flight")
	assert_null(plan.prediction(),
			"the strict accessor stays empty until the run finishes")

	var partial := plan.prediction_partial()
	assert_not_null(partial, "the partial is readable straight away")
	assert_eq(partial.trajectory.samples.size(), 5,
			"the rest pose plus the four samples resolved so far")
	assert_lt(partial.trajectory.samples.size(), _swing_steps(),
			"fixture: a whole swing is longer than one slice")

	plan.advance_prediction(4)
	assert_same(plan.prediction_partial(), partial,
			"a later range extends the SAME bundle — the ghost holds a handle on it")
	assert_eq(partial.trajectory.samples.size(), 9, "and the arc grew in place")

	_slice_to_completion(plan, 4)
	assert_same(plan.prediction(), partial,
			"and the finished prediction is that same bundle, complete")


## [b]Acceptance 3.[/b] A click landing mid-slice supersedes the run in flight:
## the stale one is dropped rather than allowed to finish, so it can never
## overwrite the fresher prediction. Every input to the resolve routes through
## `_invalidate_prediction`, which is where the cancellation lives.
func test_a_click_mid_slice_yields_the_new_selection_never_the_old() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	var plan := await _arm()

	plan._invalidate_prediction()
	assert_false(plan.advance_prediction(4), "fixture: the run must still be in flight")
	var stale := plan.prediction_partial()
	assert_eq(stale.trajectory.samples[0].size(), 3,
			"fixture: the superseded run describes a three-vertex blade")

	# Drop the tip through the real click path — the same invalidation every
	# state change shares.
	plan._on_node_left_clicked(_tip)
	assert_not_same(plan.prediction_partial(), stale,
			"the superseded run is dropped, never resumed")

	plan.refresh_prediction()
	var fresh := plan.prediction()
	assert_not_same(fresh, stale, "the completed prediction is not the stale run's")
	assert_eq(fresh.trajectory.samples[0].size(), 2,
			"it describes the NEW selection — two vertices, the tip is gone")


## [b]Acceptance 1, from the behaviour side.[/b] The click itself buys ONE
## slice, not a whole resolve — that is the stall the issue is about — and the
## preview's own per-frame pump finishes it a handful of frames later.
func test_the_mounted_preview_slices_the_resolve_across_frames() -> void:
	await _setup(Vector2.from_angle(_TURNS * TAU) * _SPACING)
	var plan := await _arm()

	assert_true(plan.is_predicting(),
			"arming buys one slice, not the whole resolve (#821)")
	assert_null(plan.prediction(), "so the completed cache is still empty")
	assert_lt(plan.prediction_partial().trajectory.samples.size(), _swing_steps(),
			"the arc drawn on the click frame is a partial one")

	for _i in 30:
		await get_tree().process_frame
		if plan.prediction() != null:
			break
	assert_not_null(plan.prediction(),
			"the preview's per-frame pump finishes it without another click")
	assert_eq(plan.prediction().trajectory.samples.size(), _swing_steps() + 1,
			"and what it finishes on is the whole swing")
