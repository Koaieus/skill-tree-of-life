extends GutTest

## #466 — "reform last blade": the player's last successfully launched melee
## blade is remembered per entity for the whole run and rebuilt on demand.
##
## The issue originally proposed a superset-tolerant topology hash of the owned
## subgraph. There isn't one — a hash that has to accept an allocation superset
## is ill-defined. What replaced it is replaying the stored stable ids through
## the SAME gates a click sequence passes, which is exact rather than a proxy;
## `test_reform_still_works_after_territory_grows` is the case the hash existed
## for, and it falls out for free.
##
## The other thing pinned here is strictness. The melee sandbox used to re-arm
## by pushing its remembered nodes back through `route_left_click`, which lands
## in `_try_select_path` — so a member that had drifted out of adjacency
## silently mass-selected a path to itself and re-armed a DIFFERENT, larger
## blade while reporting success. Reform must refuse instead.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _pic: PlayerInputController
var _attacker: Entity

## pivot — joint — tip, plus `spur` hanging off the pivot, all owned by
## `_attacker`. The spur is the "extra territory" the superset case allocates.
var _pivot: SkillNode
var _joint: SkillNode
var _tip: SkillNode
var _spur: SkillNode

## `can_reform()` sampled each time the plan cleared, for the applier-timing
## case. A script member rather than a local a lambda closes over — a lambda
## captures locals BY VALUE, so an outer counter never moves.
var _gate_on_clear: Array[bool] = []


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_gate_on_clear = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	# No MeleePreview and no AttackVFX on purpose: _commit then has no animation
	# to await, so a launch settles in a couple of frames.
	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	add_child(_bs)

	_attacker = _make_entity("Attacker")
	_tm.current_entity = _attacker

	_pic = autofree(PlayerInputController.new())
	_pic.graph = _graph
	_pic.allocation_system = _alloc
	_pic.battle_system = _bs
	_pic.turn_manager = _tm
	_pic.player = _attacker
	add_child(_pic)

	_pivot = _spawn("Pivot")
	_joint = _spawn("Joint")
	_tip = _spawn("Tip")
	_spur = _spawn("Spur")
	_graph.add_edge(_pivot, _joint)
	_graph.add_edge(_joint, _tip)
	_graph.add_edge(_pivot, _spur)
	await get_tree().process_frame

	for n in [_pivot, _joint, _tip]:
		_alloc.force_allocate(_attacker, n)


func _record_reform_gate_on_clear(plan: AttackPlan) -> void:
	if plan == null:
		_gate_on_clear.append(_pic.can_reform())


func _make_entity(nm: String) -> Entity:
	var e := Entity.new()
	e.name = nm
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.stat_board.blade_size.base_value = 3.0
	e.stat_board.action_points.set_base_ratcheted(4.0)
	e.stat_board.action_points.current = 4.0
	# entities_container, not the Graph itself: `entity_id` mints on entry
	# there, and CommandApplier resolves a command's actor by that id.
	_graph.entities_container.add_child(e)
	return e


## Arm melee and click-build pivot → members through the REAL input path, so
## every gate a player passes is exercised before the capture.
func _click_build(members: Array[SkillNode]) -> MeleeAttackPlan:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	for m in members:
		plan._on_node_left_clicked(m)
	return plan


func _launch_and_settle(max_ticks: int = 300) -> void:
	_bs.launch_attack()
	var ticks := 0
	while _bs.is_launching and ticks < max_ticks:
		await get_tree().process_frame
		ticks += 1
	assert_false(_bs.is_launching, "the swing must settle (ticks=%d)" % ticks)


## Blade as a comparable set of node names — order is an implementation detail
## of the replay, the SET is the contract.
func _blade_names(plan: MeleeAttackPlan) -> Array[String]:
	var names: Array[String] = []
	for n in plan.blade_nodes:
		names.append(String(n.name))
	names.sort()
	return names


# ── Capture ────────────────────────────────────────────────────────────────

## The canary for the pure predicate: `can_reform_selection` re-implements the
## gates `_try_select_blade` enforces rather than running them, so a blade the
## real click path just built MUST reform. This fails the day those two drift.
func test_a_click_built_blade_can_always_be_reformed() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	assert_true(_pic.can_reform(), "the blade that just launched must be reformable")
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["Joint", "Tip"])
	assert_eq((_bs.attack_plan as MeleeAttackPlan).source, _pivot)


func test_nothing_to_reform_before_the_first_launch() -> void:
	_click_build([_joint])
	assert_false(_pic.can_reform(), "building a blade is not launching one")
	assert_false(_pic.reform_blade())


func test_swing_direction_is_restored_onto_the_sticky_preference() -> void:
	var plan := _click_build([_joint])
	_bs.next_melee_cw = true
	plan.swing_cw = true
	await _launch_and_settle()
	# Flip the preference away, so a restore is observable rather than a no-op.
	_bs.next_melee_cw = false
	assert_true(_pic.reform_blade())
	assert_true((_bs.attack_plan as MeleeAttackPlan).swing_cw)
	assert_true(_bs.next_melee_cw,
			"the tray's swing toggle reads BattleSystem, so the restore has to land there too")


func test_reform_emits_plan_state_changed() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	# A lambda captures locals by value — count into a reference type.
	var seen: Array[int] = []
	_bs.attack_plan_state_changed.connect(func() -> void: seen.append(1))
	assert_true(_pic.reform_blade())
	assert_gt(seen.size(), 0,
			"MeleeBody's blips and MeleePreview refresh off this signal")


# ── Availability ───────────────────────────────────────────────────────────

func test_reform_is_refused_when_a_member_is_no_longer_owned() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	_alloc.force_deallocate(_tip)
	# A live (empty) melee plan, so the "left untouched" assertions below have
	# something to observe — the launch cleared the previous one.
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	assert_not_null(plan, "fixture: melee must be armed")

	assert_false(_pic.can_reform(), "a blade missing a member is not reformable")
	assert_false(_pic.reform_blade())
	assert_null(plan.source, "no partial blade — the plan is left untouched")
	assert_true(plan.blade_nodes.is_empty(), "no partial blade")


func test_reform_recovers_when_the_member_is_allocated_again() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	_alloc.force_deallocate(_tip)
	assert_false(_pic.can_reform())

	_alloc.force_allocate(_attacker, _tip)
	assert_true(_pic.can_reform(), "the blade is constructible again")
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["Joint", "Tip"])


## The case the topology hash was invented for. Territory GREW — a strict
## superset of what the blade was captured against — and the old blade is still
## exactly constructible, so reform must succeed and must not drag the new node
## in with it.
func test_reform_still_works_after_territory_grows() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	_alloc.force_allocate(_attacker, _spur)

	assert_true(_pic.can_reform(), "a superset of the old territory still fits the old blade")
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["Joint", "Tip"],
			"the newly allocated node is not part of the remembered blade")


func test_reform_is_refused_when_the_blade_no_longer_fits_blade_size() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()
	_attacker.stat_board.blade_size.base_value = 1.0

	assert_false(_pic.can_reform(), "two members no longer fit a blade_size of one")


func test_a_refused_launch_does_not_overwrite_the_slot() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()

	# Arm a DIFFERENT blade, then starve it of AP so _compute_record
	# refuses. attack_launched never fires, so the slot must still hold the
	# first blade.
	_alloc.force_allocate(_attacker, _spur)
	var second := _click_build([_spur])
	assert_true(second.is_valid(), "fixture: the second blade must be launchable on paper")
	_attacker.stat_board.action_points.current = 0.0
	await _launch_and_settle()

	_attacker.stat_board.action_points.current = 4.0
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["Joint", "Tip"],
			"a launch that never cleared the AP gate must not replace the remembered blade")


# ── Strictness (the sandbox's old half-reform) ─────────────────────────────

## `_try_select_path` would mass-select Pivot→Joint→Tip and report success with
## a bigger blade than asked for. try_reform must refuse outright.
func test_reform_never_mass_selects_a_path_to_a_detached_member() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	var members: Array[SkillNode] = [_tip]  # two hops out; Joint is between

	assert_false(MeleeAttackPlan.can_reform_selection(_attacker, _pivot, members))
	assert_false(plan.try_reform(_pivot, members))
	assert_null(plan.source, "a refused reform leaves the plan empty")
	assert_true(plan.blade_nodes.is_empty(),
			"never the mass-select path — that is the half-reform #466 forbids")


## Accepted limitation, pinned deliberately: the replay walks the stored order,
## so a set that is only constructible in a different order is refused rather
## than reordered.
func test_reform_walks_the_stored_order_and_does_not_search_for_another() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	var backwards: Array[SkillNode] = [_tip, _joint]
	var forwards: Array[SkillNode] = [_joint, _tip]

	assert_false(plan.try_reform(_pivot, backwards),
			"Tip is not adjacent to the pivot yet at that point in the walk")
	assert_true(plan.try_reform(_pivot, forwards), "the authoring order always replays")


# ── Timing under a CommandApplier ──────────────────────────────────────────

## Why the melee sandbox's auto re-arm cannot fire straight out of
## `attack_plan_changed`. `_commit` clears the plan (`_reset()`) from INSIDE the
## launch command's drain, so `is_applying` is still true at that moment and
## `can_player_act()` — which `can_reform()` inherits — refuses. The window
## opens on `applying_changed(false)`, which is what the panel now waits for.
##
## This is not a hypothetical: the old re-arm pushed its remembered nodes back
## through `route_left_click`, hit the same gate, and had been a silent no-op.
func test_reform_is_gated_shut_until_the_launch_command_finishes_draining() -> void:
	# NOT `var applier := autofree(...)` — autofree() returns untyped, so `:=`
	# cannot infer, and GUT skips the whole file while still reporting green.
	var applier := CommandApplier.new()
	autofree(applier)
	applier.graph = _graph
	applier.allocation_system = _alloc
	applier.battle_system = _bs
	applier.turn_manager = _tm
	add_child(applier)
	_bs.command_applier = applier
	_pic.command_applier = applier

	_click_build([_joint, _tip])

	_bs.attack_plan_changed.connect(_record_reform_gate_on_clear)

	await _launch_and_settle()
	# The drain outlives is_launching by a hair; settle it too.
	var ticks := 0
	while applier.is_applying and ticks < 300:
		await get_tree().process_frame
		ticks += 1

	assert_eq(_gate_on_clear.size(), 1, "the plan clears exactly once, post-launch")
	assert_false(_gate_on_clear[0],
			"reform is refused while the launch command is still draining")
	assert_true(_pic.can_reform(),
			"and available once the applier goes idle — the sandbox's re-arm cue")


# ── Hot seat ───────────────────────────────────────────────────────────────

## The slot is keyed per entity, so a handover cannot let the incoming player
## reform the outgoing one's blade.
func test_each_entity_reforms_its_own_blade() -> void:
	_click_build([_joint, _tip])
	await _launch_and_settle()

	var other := _make_entity("Other")
	_alloc.force_allocate(other, _spur)
	var other_leaf := _spawn("OtherLeaf")
	_graph.add_edge(_spur, other_leaf)
	await get_tree().process_frame
	_alloc.force_allocate(other, other_leaf)

	_tm.current_entity = other
	_pic.player = other
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_false(_pic.can_reform(), "the incoming player has no blade of their own yet")

	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_spur)
	plan._on_node_left_clicked(other_leaf)
	await _launch_and_settle()
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["OtherLeaf"])

	# Hand back: the first player's blade is still exactly where it was.
	_tm.current_entity = _attacker
	_pic.player = _attacker
	assert_true(_pic.reform_blade())
	assert_eq(_blade_names(_bs.attack_plan as MeleeAttackPlan), ["Joint", "Tip"])
