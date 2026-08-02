extends GutTest

## Tooltip V2 (#226/#314) — the TooltipFan coordinator: anchoring, per-index
## stagger, teardown, and the live gating that replaced occupancy-class variant
## selection. Per the coordinator's own contract it owns no Tween and no
## fan-wide progress variable — see the source-inspection tests at the bottom,
## which assert that structurally rather than trusting it stays true after the
## next edit.
##
## Variant selection is gone: there is one `fan.tscn` and every unit gates
## itself through `has_content()`. The tests that used to pin `_pick_variant`'s
## three branches are replaced by the behaviour that mattered underneath them —
## allocating the node you are hovering makes Owner/Core appear WITHOUT
## re-fanning, which the variant design could not do at all.

const _FAN_SCENE := preload("res://ui/tooltip_fan/tooltip_fan.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _fan: TooltipFan
var _node: SkillNode
var _entity: Entity


func before_each() -> void:
	_fan = _FAN_SCENE.instantiate() as TooltipFan
	_fan.stagger_delay = 0.01
	add_child(_fan)
	autofree(_fan)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(_node)
	autofree(_node)

	_entity = autofree(Entity.new())
	# A real board, not a bare Entity: the core-HP watch resolves through
	# `owned_by.stat_board.get_stat(&"health")`, so an entity without one
	# exercises only the null guard. Same `duplicate(true)` fixture pattern as
	# test_intent_dispatch / test_serpent_core.
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	add_child(_entity)


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.core_location = null


# --- one fan scene, gated per unit --------------------------------------------

func test_hovering_mounts_the_one_fan_scene() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_not_null(_fan._current_fan)
	assert_true(_fan.visible)
	assert_eq(_fan._current_fan.scene_file_path, _fan.fan_scene.resource_path,
		"every hover mounts the same scene — there are no variants to pick between")


func test_an_unowned_node_gates_out_the_owner_and_core_units() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_false(_unit("Owner").participating, "no owning entity, so no Owner panel")
	assert_false(_unit("Core").participating, "not a core, so no Core panel")


func test_an_owned_non_core_node_gates_in_owner_but_not_core() -> void:
	_node.owned_by = _entity
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_true(_unit("Owner").participating, "an owned node discloses its owner")
	assert_false(_unit("Core").participating, "an owned non-core node has no core manifest")


func test_an_owned_core_node_gates_in_both() -> void:
	_entity.core_location = _node
	_node.owned_by = _entity
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_true(_unit("Owner").participating)
	assert_true(_unit("Core").participating)


func test_a_gated_out_unit_never_plays_in() -> void:
	Events.skill_node_hovered.emit(_node)
	# Long enough for every stagger slot to have elapsed.
	for _i in range(30):
		await get_tree().process_frame
	assert_eq(_unit("Owner").state, FanUnit.State.HIDDEN,
		"a suppressed unit must stay HIDDEN, not show an empty box")


# --- #314: live response to node state ----------------------------------------

func test_allocating_the_hovered_node_fans_the_owner_panel_in() -> void:
	# The case the occupancy-class variants could not serve at all: ownership
	# flips while the pointer never moves.
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_false(_unit("Owner").participating, "precondition: Owner starts gated out")

	_node.owned_by = _entity
	_node.owner_changed.emit()
	await get_tree().process_frame

	assert_true(_unit("Owner").participating, "allocation must make the Owner panel eligible")
	var frames := 0
	while _unit("Owner").state == FanUnit.State.HIDDEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_ne(_unit("Owner").state, FanUnit.State.HIDDEN,
		"an eligible unit must actually play in, not merely be flagged")


func test_allocating_the_hovered_node_leaves_the_open_panels_alone() -> void:
	# "The panels already up stay up" — the whole reason this isn't a re-fan.
	Events.skill_node_hovered.emit(_node)
	var frames := 0
	while _unit("IdChip").state == FanUnit.State.HIDDEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	var chip := _unit("IdChip")
	assert_ne(chip.state, FanUnit.State.HIDDEN, "precondition: the ID chip is up")
	var fan_before := _fan._current_fan

	_node.owned_by = _entity
	_node.owner_changed.emit()
	await get_tree().process_frame

	assert_eq(_fan._current_fan, fan_before, "allocation must not remount the fan")
	assert_same(_unit("IdChip"), chip, "the ID chip unit must be the same instance")
	assert_ne(chip.state, FanUnit.State.HIDDEN, "and must not have been torn down")


func test_deallocating_the_hovered_node_fans_the_owner_panel_out() -> void:
	_node.owned_by = _entity
	Events.skill_node_hovered.emit(_node)
	var frames := 0
	while _unit("Owner").state == FanUnit.State.HIDDEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_ne(_unit("Owner").state, FanUnit.State.HIDDEN, "precondition: Owner is up")

	_node.owned_by = null
	_node.owner_changed.emit()
	await get_tree().process_frame

	assert_false(_unit("Owner").participating, "losing the owner must gate the panel out")
	frames = 0
	while _unit("Owner").state != FanUnit.State.HIDDEN and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_eq(_unit("Owner").state, FanUnit.State.HIDDEN, "and it must animate away, not just stop")


func test_damage_on_the_hovered_node_rebinds_without_remounting() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	var fan_before := _fan._current_fan
	_node.damaged.emit(5.0, null)
	await get_tree().process_frame
	assert_eq(_fan._current_fan, fan_before,
		"an HP update re-reads the node into the open panels; it does not re-fan")


func test_unhovering_drops_the_live_subscriptions() -> void:
	# The leak this ordering exists to prevent: retiring is asynchronous, so a
	# fan mid-fade is still alive and would re-ignite on the next damage tick if
	# it were still listening.
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	Events.skill_node_unhovered.emit()
	assert_false(_node.owner_changed.is_connected(_fan._on_owner_changed),
		"owner_changed must be disconnected on unhover")
	assert_false(_node.damaged.is_connected(_fan._on_node_damaged),
		"damaged must be disconnected on unhover")


func test_hovering_a_second_node_moves_the_subscriptions_to_it() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	var node_b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(node_b)
	autofree(node_b)

	Events.skill_node_hovered.emit(node_b)
	await get_tree().process_frame

	assert_false(_node.damaged.is_connected(_fan._on_node_damaged),
		"the old node must be released")
	assert_true(node_b.damaged.is_connected(_fan._on_node_damaged),
		"and the new one picked up")


func test_a_core_nodes_owner_health_is_watched_and_released() -> void:
	_entity.core_location = _node
	_node.owned_by = _entity
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_not_null(_fan._core_health_stat,
		"hovering a core node must watch its owner's health pool")
	Events.skill_node_unhovered.emit()
	assert_null(_fan._core_health_stat, "and release it on unhover")


func test_an_unowned_node_watches_no_health_pool() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_null(_fan._core_health_stat, "there is no owner, so there is nothing to watch")


# --- anchoring ---------------------------------------------------------------

func test_hovering_anchors_the_fan_to_the_nodes_canvas_position() -> void:
	_node.global_position = Vector2(240.0, 80.0)
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	var expected: Vector2 = _node.get_global_transform_with_canvas().origin
	assert_almost_eq(_fan.global_position.x, expected.x, 0.5)
	assert_almost_eq(_fan.global_position.y, expected.y, 0.5)


func test_fan_tracks_the_node_across_subsequent_frames() -> void:
	_node.global_position = Vector2(0.0, 0.0)
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	_node.global_position = Vector2(400.0, -120.0)
	await get_tree().process_frame
	var expected: Vector2 = _node.get_global_transform_with_canvas().origin
	assert_almost_eq(_fan.global_position.x, expected.x, 0.5)
	assert_almost_eq(_fan.global_position.y, expected.y, 0.5)


func test_unhovering_eventually_frees_the_fan() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	Events.skill_node_unhovered.emit()
	# Retiring is async (each member's own play_out sequence); poll a bounded
	# number of frames rather than assuming a fixed frame count.
	var frames := 0
	while _fan._current_fan != null and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_null(_fan._current_fan, "the fan should be freed once every member settles to HIDDEN")


func test_hovering_a_second_node_retires_the_first_fan_frozen_in_place() -> void:
	# Regression guard for two bugs found in review:
	#  1. `_play_in_one` not checking the `retiring` meta -> a still-pending
	#     delayed play_in() fires on a member of a fan already being torn
	#     down, and `_all_settled` never turns true again (permanent leak).
	#  2. Freezing the outgoing fan's position using `global_position`
	#     AFTER it had already been reassigned to the NEW node -> the old
	#     fan teleports to the new node's spot instead of fading where it
	#     actually was.
	_node.global_position = Vector2(0.0, 0.0)
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame

	# Wait until the fan is ACTUALLY up before superseding it. Both bugs this
	# guards are about tearing down a fan mid-animation, so a fan with every
	# member still HIDDEN doesn't exercise either — and that is a reachable
	# state: `FanPanel.has_content()` suppresses panels with nothing to show,
	# and this fixture's bare SkillNode has no addons, no owner and no
	# node-local stats, so those panels legitimately never play in. Whichever
	# member is first in angular order, poll until something is animating.
	var fired := 0
	while not _any_member_active() and fired < 120:
		await get_tree().process_frame
		fired += 1
	assert_true(_any_member_active(), "A's fan should have at least one member animating")

	var node_b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(node_b)
	autofree(node_b)
	node_b.global_position = Vector2(500.0, 500.0)

	var old_fan := _fan._current_fan
	assert_not_null(old_fan, "A's hover should have mounted a fan")
	var expected_a_pos: Vector2 = _node.get_global_transform_with_canvas().origin

	Events.skill_node_hovered.emit(node_b)
	await get_tree().process_frame

	assert_ne(_fan._current_fan, old_fan, "B's hover should mount its own instance")
	assert_true(is_instance_valid(old_fan), "A's fan should still be retiring, not yet freed")
	assert_almost_eq((old_fan as Node2D).global_position.x, expected_a_pos.x, 0.5,
		"A's outgoing fan must stay frozen at A's spot, not jump to B's")
	assert_almost_eq((old_fan as Node2D).global_position.y, expected_a_pos.y, 0.5)

	var frames := 0
	while is_instance_valid(old_fan) and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_false(is_instance_valid(old_fan),
		"A's fan must eventually be freed, not leak forever behind the retiring guard")


# --- per-index stagger --------------------------------------------------------

func test_members_are_fired_with_an_increasing_per_index_delay() -> void:
	# A generous delay, not the fixture's 0.01s default: a single
	# process_frame on a slow/headless run can exceed 10ms on its own, which
	# would flake this assertion for reasons unrelated to the stagger logic.
	_fan.stagger_delay = 5.0
	# An OWNED node, so several units participate. A bare unowned node leaves
	# only the ID chip eligible, which makes a stagger assertion vacuous — and
	# the stagger indexes over PARTICIPATING members (#314), not over every
	# authored one, so those are the only members whose delay slot is defined.
	_node.owned_by = _entity
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	var live := _participating_units()
	assert_gt(live.size(), 1, "an owned node should leave more than one unit eligible")
	# Immediately after hover, nothing should have started yet except the
	# zero-delay first member — later members must still be at HIDDEN until
	# their own delay elapses.
	var later_started := false
	for i in range(1, live.size()):
		if live[i].state != FanUnit.State.HIDDEN:
			later_started = true
	assert_false(later_started, "later members must not start on the same frame as the first")
	assert_ne(live[0].state, FanUnit.State.HIDDEN, "the zero-delay member should have started")


# --- structural: no Tween, no fan-wide progress -----------------------------

## The coordinator decides WHEN each member starts and nothing else — no
## fan-wide clock the members read off. Asserted against the real property
## list, not by grepping the script's source text: a source grep passes just as
## happily after a rename to `var _progress`, and would fail on a doc comment
## that merely mentions the name, so it checks neither direction of the thing
## it claims to check.
##
## (Its deleted sibling grepped for `create_tween(`. There is no public "which
## node bound this Tween" API to replace it with, and the invariant it named is
## covered behaviourally by the stagger test above — members must start on
## their own delays, which a shared tween would break.)
func test_coordinator_has_no_fan_wide_progress_variable() -> void:
	for prop in _fan.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_ne(String(prop["name"]).lstrip("_"), "progress",
				"TooltipFan must not own a fan-wide progress clock (found `%s`)" % prop["name"])


# --- helpers -----------------------------------------------------------------

## The named [FanUnit] inside the currently-mounted fan. Re-resolved per call
## rather than cached, so a test that accidentally remounts sees the new
## instance instead of asserting against a stale one.
func _unit(unit_name: String) -> FanUnit:
	assert_not_null(_fan._current_fan, "no fan is mounted")
	return _fan._current_fan.find_child(unit_name, true, false) as FanUnit


## The eligible [FanUnit]s of the mounted fan, in the angular order the
## coordinator hands out stagger slots in. This — not the full member list — is
## what `_play_in_all` indexes over since #314, so it's the only sequence a
## stagger assertion can be written against.
func _participating_units() -> Array[FanUnit]:
	var out: Array[FanUnit] = []
	for m in _fan._collect_members(_fan._current_fan):
		if m is FanUnit and (m as FanUnit).participating:
			out.append(m as FanUnit)
	return out


## True once any member of the current fan has left HIDDEN — i.e. the fan
## is actually animating. Used instead of "wait one frame and assume", which
## only held while every panel unconditionally played in.
func _any_member_active() -> bool:
	var fan_instance: Node = _fan._current_fan
	if fan_instance == null or not is_instance_valid(fan_instance):
		return false
	for m in _fan._collect_members(fan_instance):
		if m is FanUnit:
			if (m as FanUnit).state != FanUnit.State.HIDDEN:
				return true
		elif m.visible:
			return true
	return false
