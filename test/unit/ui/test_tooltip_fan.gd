extends GutTest

## Tooltip V2 (#226) — the TooltipFan coordinator: anchoring, occupancy-class
## variant selection, per-index stagger, and teardown. Per the coordinator's
## own contract it owns no Tween and no fan-wide progress variable — see the
## source-inspection tests at the bottom, which assert that structurally
## rather than trusting it stays true after the next edit.

const _FAN_SCENE := preload("res://ui/tooltip_fan/tooltip_fan.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

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
	add_child(_entity)


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.core_location = null


# --- occupancy-class variant selection --------------------------------------

func test_unowned_node_picks_the_unowned_variant() -> void:
	assert_eq(_fan._pick_variant(_node), _fan.unowned_variant)


func test_owned_non_core_node_picks_the_owned_variant() -> void:
	_node.owned_by = _entity
	assert_eq(_fan._pick_variant(_node), _fan.owned_variant)


func test_owned_core_node_picks_the_owned_core_variant() -> void:
	_entity.core_location = _node
	_node.owned_by = _entity
	assert_eq(_fan._pick_variant(_node), _fan.owned_core_variant)


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


func test_hovering_spawns_a_variant_instance_and_shows_the_fan() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	assert_not_null(_fan._current_variant)
	assert_true(_fan.visible)


func test_unhovering_eventually_frees_the_variant_and_hides_the_fan() -> void:
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	Events.skill_node_unhovered.emit()
	# Retiring is async (each member's own play_out sequence); poll a bounded
	# number of frames rather than assuming a fixed frame count.
	var frames := 0
	while _fan._current_variant != null and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_null(_fan._current_variant, "variant should be freed once every member settles to HIDDEN")


func test_hovering_a_second_node_retires_the_first_variant_frozen_in_place() -> void:
	# Regression guard for two bugs found in review:
	#  1. `_play_in_one` not checking the `retiring` meta -> a still-pending
	#     delayed play_in() fires on a member of a variant already being torn
	#     down, and `_all_settled` never turns true again (permanent leak).
	#  2. Freezing the outgoing variant's position using `global_position`
	#     AFTER it had already been reassigned to the NEW node -> the old
	#     fan teleports to the new node's spot instead of fading where it
	#     actually was.
	_node.global_position = Vector2(0.0, 0.0)
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame

	# Wait until the fan is ACTUALLY up before superseding it. Both bugs this
	# guards are about tearing down a fan mid-animation, so a variant with
	# every member still HIDDEN doesn't exercise either — and that is now a
	# reachable state: `FanPanel.has_content()` suppresses panels with nothing
	# to show, and this fixture's bare SkillNode has no addons and no
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

	var old_variant := _fan._current_variant
	assert_not_null(old_variant, "A's fan should have spawned a variant")
	var expected_a_pos: Vector2 = _node.get_global_transform_with_canvas().origin

	Events.skill_node_hovered.emit(node_b)
	await get_tree().process_frame

	assert_ne(_fan._current_variant, old_variant, "B's hover should spawn its own variant")
	assert_true(is_instance_valid(old_variant), "A's variant should still be retiring, not yet freed")
	assert_almost_eq((old_variant as Node2D).global_position.x, expected_a_pos.x, 0.5,
		"A's outgoing fan must stay frozen at A's spot, not jump to B's")
	assert_almost_eq((old_variant as Node2D).global_position.y, expected_a_pos.y, 0.5)

	var frames := 0
	while is_instance_valid(old_variant) and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_false(is_instance_valid(old_variant),
		"A's variant must eventually be freed, not leak forever behind the retiring guard")


# --- per-index stagger --------------------------------------------------------

func test_members_are_fired_with_an_increasing_per_index_delay() -> void:
	# A generous delay, not the fixture's 0.01s default: a single
	# process_frame on a slow/headless run can exceed 10ms on its own, which
	# would flake this assertion for reasons unrelated to the stagger logic.
	_fan.stagger_delay = 5.0
	Events.skill_node_hovered.emit(_node)
	await get_tree().process_frame
	var members := _fan._collect_members(_fan._current_variant)
	assert_gt(members.size(), 1, "unowned variant should have more than one fan member")
	# Immediately after hover, nothing should have started yet except
	# possibly the zero-delay first member — later members must still be
	# at HIDDEN/invisible until their own delay elapses.
	var later_started := false
	for i in range(1, members.size()):
		var m = members[i]
		if m is FanUnit and (m as FanUnit).state != FanUnit.State.HIDDEN:
			later_started = true
	assert_false(later_started, "later members must not start on the same frame as the first")


# --- structural: no Tween, no fan-wide progress -----------------------------

func test_coordinator_owns_no_tween() -> void:
	var src := FileAccess.get_file_as_string("res://ui/tooltip_fan/tooltip_fan.gd")
	assert_false(src.contains("create_tween("), "TooltipFan must not own a Tween")


func test_coordinator_has_no_fan_wide_progress_variable() -> void:
	var src := FileAccess.get_file_as_string("res://ui/tooltip_fan/tooltip_fan.gd")
	assert_false(src.contains("var progress"), "TooltipFan must not own a fan-wide progress clock")


# --- helpers -----------------------------------------------------------------

## True once any member of the current variant has left HIDDEN — i.e. the fan
## is actually animating. Used instead of "wait one frame and assume", which
## only held while every panel unconditionally played in.
func _any_member_active() -> bool:
	var variant: Node = _fan._current_variant
	if variant == null or not is_instance_valid(variant):
		return false
	for m in _fan._collect_members(variant):
		if m is FanUnit:
			if (m as FanUnit).state != FanUnit.State.HIDDEN:
				return true
		elif m.visible:
			return true
	return false
