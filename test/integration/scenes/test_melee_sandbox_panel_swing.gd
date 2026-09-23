extends GutTest

## The melee sandbox panel's one real-clock swing. A right-click while a swing is
## in flight must be refused like it is in game — that needs the in-flight
## window, which `BattleSystem.instant_mutation` collapses, so it lives here
## (docs/domain/testing-tiers.md) and not beside the panel's unit smoke tests in
## `test/unit/scenes/test_melee_sandbox_panel.gd`.

const _PANEL := preload("res://addons/melee_sandbox/melee_sandbox_panel.tscn")

var _panel: PanelContainer


func before_each() -> void:
	_panel = _PANEL.instantiate() as PanelContainer
	add_child_autofree(_panel)
	# GUT never marks the panel visible, and a dormant tab is deliberately
	# process-disabled — which takes its Area2Ds out of the physics broadphase,
	# so no swing could hit anything. Waking it is a prerequisite here.
	_panel.set_live(true)
	# Two physics frames: melee hit detection is a physics-server sweep
	# (BladeHitScan), so the world's Area2Ds must be in the broadphase first.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _node(n: String) -> SkillNode:
	return _panel.graph.skill_nodes_container.get_node(n) as SkillNode


## Grow a launchable blade off the hilt and hand back the live plan.
func _build_blade() -> MeleeAttackPlan:
	_panel._blade_size.value = 8
	for n in ["Hilt", "Guard", "B1", "B2", "B3"]:
		_panel._input_ctl.route_left_click(_node(n))
	return _panel._battle.attack_plan as MeleeAttackPlan


## The panel's own right-click carrier, node-independent like the real one.
func _right_click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2.ZERO
	_panel._on_world_gui_input(ev)


func test_a_right_click_mid_swing_is_refused_like_it_is_in_game() -> void:
	# The panel calls `pop()` raw, reaching past AttackPlanArmedMode — the only
	# place the game gates right-click. Un-gated, a mid-swing right-click tears
	# down the plan the launch is still running on.
	var battle: BattleSystem = _panel._battle
	var plan := _build_blade()
	assert_true(plan.is_valid(), "the fixture must have a launchable blade")
	battle.launch_attack()  # deliberately un-awaited: we need the await window
	await get_tree().process_frame
	assert_true(battle.is_launching, "the swing must still be in flight to test this")
	_right_click()
	assert_not_null(plan.source, "a swing in flight must keep the plan it is swinging")
	# The ghost the wind-up claimed IS the blade that swings (MeleePreview.launch).
	var swung: Object = _panel._preview.current_blade()
	assert_not_null(swung, "the swing must be drawing a blade")
	# Budget covers the #559 wind-up as well as the swing itself — a committed
	# melee is staged now (form beat, then swing), so "in flight" lasts longer
	# than SWING_DURATION. Wall clock, not ticks: the swing runs on real-second
	# timers while the headless frame period is a test-hook knob that varies by
	# an order of magnitude between machines.
	var settled: bool = await wait_until(func() -> bool: return not battle.is_launching, 15.0)
	assert_true(settled, "and the swing must still finish")
	# The swung blade may fade out a little past `is_launching`; the preview
	# frees it once the fade finishes, and only then mounts fresh ghosts.
	var swung_ref: WeakRef = weakref(swung)  # a lambda capturing a freed Object errors
	assert_true(await wait_until(func() -> bool: return swung_ref.get_ref() == null, 2.0),
			"the swung blade must fade out and free itself")
	# The tab has to still DRAW: a panel that takes clicks but mounts no ghost
	# reads as broken even when every system underneath is fine.
	_build_blade()
	assert_not_null(_panel._preview.current_blade(),
			"a fresh selection must still mount a ghost afterwards")
