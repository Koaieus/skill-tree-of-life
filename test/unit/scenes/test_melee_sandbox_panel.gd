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
