extends GutTest

## #309 — the LIVE fan bench driver (`fan_live_sandbox.gd`): hosts the real
## `fan.tscn`, binds a real SkillNode + Entity fixture exactly like TooltipFan,
## and drives the fan's actual inputs (presets, fixture knobs, participation
## overrides, driver knobs, drive modes, scrub, drag). The old mock sandbox
## had no tests at all — that drift is what this issue exists to retire, so the
## replacement bench gets coverage of every gate and knob it exposes.

const _SANDROB_SCRIPT := preload("res://ui/tooltip_fan/fan_live_sandbox.gd")
const _SANDBOX_SCENE := preload("res://ui/tooltip_fan/fan_live_sandbox.tscn")

var _sandbox: Node


func before_each() -> void:
	_sandbox = _SANDBOX_SCENE.instantiate()
	add_child(_sandbox)
	autofree(_sandbox)


func _unit(name: String) -> FanUnit:
	return _sandbox.find_child(name, true, false) as FanUnit


## Staggered play-ins and fade-outs run on real timers; a test that asserts on
## a unit's state must wait it out rather than read a mid-flight frame.
func _wait_until_state(name: String, state: FanUnit.State, max_frames := 180) -> void:
	var frames := 0
	while _unit(name).state != state and frames < max_frames:
		await get_tree().process_frame
		frames += 1


func _participation() -> Dictionary:
	return _sandbox.get_participation()


func _fan() -> FanAnchorDriver:
	return _sandbox.get_node("Fan") as FanAnchorDriver


# --- presets: whole-situation fixtures -----------------------------------------

func test_unallocated_preset_gates_every_conditional_unit() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_UNALLOCATED)
	var part := _participation()
	assert_true(part["IdChip"], "IdChip never gates")
	assert_false(part["NodeStats"], "unowned node with no local stats shows no NodeStats")
	assert_false(part["Addons"], "bare node has no addons")
	assert_false(part["Owner"], "no owning entity")
	assert_false(part["Core"], "not a core")
	assert_false(part["ProcgenDebug"], "no procgen footprint meta")


func test_friendly_preset_gates_in_owner_but_not_core() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_FRIENDLY)
	var part := _participation()
	assert_true(part["IdChip"])
	assert_true(part["NodeStats"], "an allocated node always shows its HP/armor rows")
	assert_true(part["Addons"], "the friendly preset carries 2 addons")
	assert_true(part["Owner"], "an owned node discloses its owner")
	assert_false(part["Core"], "an owned non-core node has no core manifest")
	assert_false(part["ProcgenDebug"])


func test_enemy_preset_marks_the_owner_hostile() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_ENEMY)
	var panel := _unit("Owner").get_node("%Panel") as OwnerPanel
	var tag: Label = panel.get_node("%HostileTag")
	assert_true(tag.visible, "an npc-faction owner must show the HOSTILE OWNER tag")
	assert_eq(tag.text, "HOSTILE OWNER")


func test_core_preset_gates_in_every_unit() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_CORE)
	var part := _participation()
	for unit_name in ["IdChip", "NodeStats", "Addons", "Owner", "Core", "ProcgenDebug"]:
		assert_true(part[unit_name], "%s should participate on the full fan" % unit_name)


# --- participation overrides ----------------------------------------------------

func test_participation_override_redistributes_the_clock_pins() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_UNALLOCATED)
	assert_eq(_fan().units_in_fan_order().size(), 1, "precondition: bare node, one pin")
	_sandbox.set_participating("Owner", true)
	assert_true(_participation()["Owner"])
	assert_eq(_fan().units_in_fan_order().size(), 2,
		"a forced-in unit takes a clock pin — the spread re-shares among participants")


func test_a_forced_out_unit_gives_up_its_pin() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_CORE)
	assert_eq(_fan().units_in_fan_order().size(), 6)
	_sandbox.set_participating("Core", false)
	assert_eq(_fan().units_in_fan_order().size(), 5,
		"gating one unit out must drop exactly one pin")


# --- driver knobs ---------------------------------------------------------------

func test_knob_writes_land_on_the_mounted_driver() -> void:
	_sandbox.set_pin_step_degrees(45.0)
	_sandbox.set_max_arc_degrees(90.0)
	_sandbox.set_pin_factor(1.2)
	_sandbox.set_pin_slide_rate(20.0)
	var driver := _fan()
	assert_eq(driver.pin_step_degrees, 45.0)
	assert_eq(driver.max_arc_degrees, 90.0)
	assert_almost_eq(driver.pin_factor, 1.2, 0.001)
	assert_eq(driver.pin_slide_rate, 20.0)


func test_zoom_feeds_node_radius_scaled_by_the_fixture_radius() -> void:
	var node: SkillNode = _sandbox.get_node("Graph/Nodes/SkillNode") as SkillNode
	_sandbox.set_zoom(2.0)
	assert_almost_eq(_fan().node_radius, node.radius * 2.0, 0.001,
		"the zoom knob must be the camera stand-in: node.radius × zoom")


# --- drive modes ----------------------------------------------------------------

func test_preset_application_fans_in_the_participating_units() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_FRIENDLY)
	var frames := 0
	while _unit("IdChip").state == FanUnit.State.HIDDEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_ne(_unit("IdChip").state, FanUnit.State.HIDDEN,
		"a participating unit must actually play in after a preset, not merely be flagged")
	assert_eq(_unit("ProcgenDebug").state, FanUnit.State.HIDDEN,
		"a gated-out unit must stay hidden on a preset that excludes it")


func test_scrub_writes_component_progress_on_participating_units_only() -> void:
	# Gated unit first — before any scrub has dirtied the fixture.
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_UNALLOCATED)
	await _wait_until_state("Owner", FanUnit.State.HIDDEN)
	_sandbox.set_scrub(0.3)
	var owner_trace: FanTrace = _unit("Owner").get_node("%Trace")
	assert_almost_eq(owner_trace.progress, 0.0, 0.01,
		"a gated-out unit is outside the fan — scrub must leave its components alone")

	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_CORE)
	_sandbox.set_scrub(0.5)
	var trace: FanTrace = _unit("IdChip").get_node("%Trace")
	var panel: FanPanel = _unit("IdChip").get_node("%Panel")
	assert_almost_eq(trace.progress, 0.5, 0.01, "scrub drives the trace reveal")
	assert_almost_eq(panel.progress, 0.5, 0.01, "scrub drives the panel reveal")


# --- fixture knobs --------------------------------------------------------------

func test_addon_count_change_reconciles_the_addons_panel() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_UNALLOCATED)
	assert_false(_participation()["Addons"], "precondition: bare node gates Addons out")
	_sandbox.set_addon_count(8)
	assert_true(_participation()["Addons"], "eight real addon scenes make Addons eligible")
	assert_eq(_sandbox.get_fixture_state()["addons"], 8)
	_sandbox.set_addon_count(0)
	assert_false(_participation()["Addons"], "removing the addons gates the panel back out")
	assert_false(_sandbox.get_fixture_state()["preset"] == _SANDROB_SCRIPT.PRESET_CORE,
		"a knob drift must clear the preset label")


func test_footprint_meta_gates_the_procgen_panel() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_UNALLOCATED)
	assert_false(_participation()["ProcgenDebug"])
	_sandbox.set_footprint(true)
	assert_true(_participation()["ProcgenDebug"], "a stamped procgen_footprint must light the debug panel")
	_sandbox.set_footprint(false)
	assert_false(_participation()["ProcgenDebug"])


func test_fixture_knobs_clear_the_preset_label() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_ENEMY)
	assert_eq(_sandbox.get_fixture_state()["preset"], _SANDROB_SCRIPT.PRESET_ENEMY)
	_sandbox.set_owned(false)
	assert_eq(_sandbox.get_fixture_state()["preset"], "",
		"drifting from a preset with a fixture knob must stop reporting the preset")


# --- drag ------------------------------------------------------------------------

func test_hit_test_finds_the_unit_under_a_point() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_CORE)
	await _wait_until_state("IdChip", FanUnit.State.LOOP)
	var unit := _unit("IdChip")
	var panel: FanPanel = unit.get_node("%Panel")
	var rect := FanAnchor.panel_rect_of(panel)
	rect.position += unit.position
	assert_eq(_sandbox.hit_test(rect.get_center()), unit,
		"the point inside a unit's panel rect must resolve to that unit")


func test_dragging_a_unit_reroutes_its_trace() -> void:
	_sandbox.apply_preset(_SANDROB_SCRIPT.PRESET_CORE)
	var unit := _unit("Owner")
	var trace: FanTrace = unit.get_node("%Trace")
	var before: Vector2 = trace.to_point
	unit.position += Vector2(60, 40)
	await get_tree().process_frame
	assert_ne(trace.to_point, before,
		"FanAnchorDriver must re-derive the terminus from the moved panel — that is the drag payoff")
