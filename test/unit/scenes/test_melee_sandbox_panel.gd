extends GutTest

## Smoke test for the melee sandbox panel. It is an editor surface, so most of
## what it proves can only be SEEN in the editor — but everything below the
## drawing is ordinary runtime code, and this drives it: the panel composes, the
## authored ownership becomes real ownership, a hand-picked click grows a blade
## through the real input channel, and Launch lands real damage.
##
## Worth having because the panel wires four systems together by hand; a broken
## wire there shows up as "the tab does nothing", with no error to read.

const _PANEL := preload("res://addons/melee_sandbox/melee_sandbox_panel.tscn")

var _panel: PanelContainer


func before_each() -> void:
	_panel = _PANEL.instantiate() as PanelContainer
	add_child_autofree(_panel)
	# GUT never marks the panel visible, and a dormant tab is deliberately
	# process-disabled — which takes its Area2Ds out of the physics broadphase,
	# so no swing could hit anything. Waking it is a prerequisite here.
	_panel.set_live(true)
	# Two physics frames, not one process frame: melee hit detection is a
	# physics-server sweep (BladeHitScan), so the world's Area2Ds have to be in
	# the broadphase before a swing can hit anything.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _node(n: String) -> SkillNode:
	return _panel.graph.skill_nodes_container.get_node(n) as SkillNode


func _wielder() -> Entity:
	return _panel.graph.entities_container.get_node("Wielder") as Entity


func test_authored_ownership_becomes_real_ownership() -> void:
	# `owned_by` in the .tscn is a declaration; only force_allocate puts a node
	# in the entity's mirror, and the mirror is what blade-growing walks.
	var wielder := _wielder()
	assert_not_null(wielder.navigator, "the panel must bring the authored entity up")
	assert_eq(wielder.navigator.get_mirrored_nodes().size(), 15,
			"all fifteen authored wielder nodes must be in the owned-subgraph mirror")


func test_a_melee_plan_is_armed_on_open() -> void:
	var battle: BattleSystem = _panel._battle
	assert_true(battle.attack_plan is MeleeAttackPlan,
			"the tab opens ready to swing — no mode picking first")
	assert_eq(battle.turn_manager.current_entity, _wielder(),
			"an attack is illegal without a current entity")


func test_clicks_grow_a_blade_through_the_real_input_channel() -> void:
	var battle: BattleSystem = _panel._battle
	var plan := battle.attack_plan as MeleeAttackPlan
	_panel._input_ctl.route_left_click(_node("Hilt"))
	assert_eq(plan.source, _node("Hilt"), "first click sets the pivot")
	_panel._input_ctl.route_left_click(_node("Guard"))
	assert_eq(plan.blade_nodes.size(), 1, "the next adjacent click grows the blade")
	# Right-click pops the pivot and every member with it.
	plan.pop()
	assert_null(plan.source, "right-click pops back to nothing")


func test_blade_size_knob_raises_the_cap() -> void:
	var plan: MeleeAttackPlan = _panel._battle.attack_plan as MeleeAttackPlan
	_panel._input_ctl.route_left_click(_node("Hilt"))
	_panel._blade_size.value = 12
	assert_eq(plan.max_blades(), 12,
			"the knob is what makes a fifteen-node blade selectable at all")


func test_a_launched_swing_damages_the_quarry() -> void:
	var battle: BattleSystem = _panel._battle
	# Instant mutation: this test reads the world on the next line, not on the
	# presentation clock (that is what the flag exists for).
	battle.instant_mutation = true
	# The panel tops the quarry up as it is hit ("spam the same swing at the same
	# board"), which would hide the very damage this test is looking for.
	_panel._topup_toggle.button_pressed = false
	_panel._blade_size.value = 8
	for n in ["Hilt", "Guard", "B1", "B2", "B3", "B4"]:
		_panel._input_ctl.route_left_click(_node(n))
	var plan := battle.attack_plan as MeleeAttackPlan
	assert_true(plan.is_valid(), "six connected picks must form a swingable blade")

	var before := 0.0
	for n in _panel.graph.get_skill_nodes():
		before += n.get_current_hp()
	await battle.launch_attack()
	var after := 0.0
	for n in _panel.graph.get_skill_nodes():
		after += n.get_current_hp()
	assert_lt(after, before, "a real swing through the real BattleSystem must land damage")
	# `launch_attack` returns when the swing is done; the ghost's fade-out runs a
	# little past that, and tearing the panel down mid-fade frees the node the
	# fade tween is writing to. Let it land before GUT's autofree sweep.
	await get_tree().create_timer(0.6).timeout


func test_a_dormant_tab_stops_simulating() -> void:
	# The owner's actual requirement: an unfocused tab must not keep crunching a
	# swing sim. Three switches, because the preview loop, the world's processing
	# and the viewport redraw are three separate costs.
	_panel.set_live(false)
	assert_eq(_panel._world.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(_panel._world.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(_panel._preview.preview_enabled, "the idle ghost loop must stop")
	_panel.set_live(true)
	assert_true(_panel._preview.preview_enabled, "and come back on focus")


func test_a_style_knob_reaches_the_blade_that_gets_built_next() -> void:
	# The knob edits a resource; the blade is rebuilt from scratch every preview
	# cycle. If the two are not connected through MeleePreview, dragging a slider
	# tunes an orphan and the tab's whole reason to exist is gone.
	var knob: BladeStyle = _panel._style
	var before := knob.rim_tier
	_panel._input_ctl.route_left_click(_node("Hilt"))
	_panel._input_ctl.route_left_click(_node("Guard"))
	knob.rim_tier = 2.5
	# Force a fresh ghost the way a selection change does.
	_panel._input_ctl.route_left_click(_node("B1"))
	var blade: SkillBlade = _panel._preview.current_blade()
	assert_not_null(blade, "a valid selection must have a ghost mounted")
	assert_eq(blade.style, knob, "the blade must read the very resource the knobs edit")
	assert_eq(blade.get_node_visuals()[0].style, knob, "and so must each vertex")
	knob.rim_tier = before


func test_forced_de_lit_survives_a_preview_rebuild() -> void:
	_panel._input_ctl.route_left_click(_node("Hilt"))
	_panel._input_ctl.route_left_click(_node("Guard"))
	_panel._delit_spin.value = 1
	assert_true(_panel._preview.current_blade().get_node_visuals()[-1].disabled,
			"the tip goes de-lit immediately")
	# The preview loop rebuilds every vertex visual each cycle; re-selecting is
	# the same rebuild, and the decoration must come back with it.
	_panel._input_ctl.route_left_click(_node("B1"))
	assert_true(_panel._preview.current_blade().get_node_visuals()[-1].disabled,
			"a rebuilt ghost must not silently drop the forced de-lit")


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


func test_an_idle_right_click_pop_leaves_the_panel_clickable() -> void:
	var plan := _build_blade()
	_right_click()
	assert_null(plan.source, "the pop clears the selection")
	assert_eq(_panel._battle.attack_plan, plan, "but never the plan itself")
	_panel._input_ctl.route_left_click(_node("Hilt"))
	assert_eq(plan.source, _node("Hilt"), "and the next click re-picks a pivot")


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
	for _i in 240:
		if not battle.is_launching:
			break
		await get_tree().process_frame
	assert_false(battle.is_launching, "and the swing must still finish")
	await get_tree().create_timer(0.6).timeout
	# The tab has to still DRAW: a panel that takes clicks but mounts no ghost
	# reads as broken even when every system underneath is fine.
	_build_blade()
	assert_not_null(_panel._preview.current_blade(),
			"a fresh selection must still mount a ghost afterwards")


func test_the_reform_slot_is_captured_in_an_editor_hosted_panel() -> void:
	# The #466 regression this file exists to catch from now on: the capture
	# hangs off `attack_launched`, which `_ready` only subscribes to. GUT sees
	# `is_editor_hint() == false`, so the guard that used to skip that whole
	# block is invisible here — assert the SUBSCRIPTION, which is not.
	# READ AS SOURCE, deliberately. Every runtime assertion here is blind to the
	# bug: GUT has `is_editor_hint() == false`, so the guard that broke this
	# never fires and the subscription happens regardless. The only check that
	# goes red on a revert is the shape of the guard itself.
	var src := FileAccess.get_file_as_string("res://systems/player_input_controller.gd")
	var ready_body := src.substr(src.find("func _ready() -> void:"))
	ready_body = ready_body.substr(0, ready_body.find("\nfunc "))
	assert_false(ready_body.contains("if Engine.is_editor_hint():\n\t\treturn"),
			"a blanket editor-hint return in _ready leaves every live sandbox tab "
			+ "half-wired — see docs/domain/sandbox-framework.md")
	var ctl: PlayerInputController = _panel._input_ctl
	assert_true(ctl.battle_system.attack_launched.is_connected(ctl._on_attack_launched),
			"the subscription Reform's slot hangs off")
	var battle: BattleSystem = _panel._battle
	battle.instant_mutation = true
	_build_blade()
	await battle.launch_attack()
	# `launch_attack` returns inside its own command's application, so the
	# applier is still draining — the very window `_flush_rearm` waits out.
	while battle.command_applier.is_applying:
		await get_tree().process_frame
	assert_true(ctl.can_reform(), "the launched blade must be reformable")
	assert_true(ctl.reform_blade(), "and Reform must rebuild it")
	var plan := battle.attack_plan as MeleeAttackPlan
	assert_eq(plan.source, _node("Hilt"), "same pivot")
	assert_eq(plan.blade_nodes.size(), 4, "same members")
	await get_tree().create_timer(0.6).timeout
