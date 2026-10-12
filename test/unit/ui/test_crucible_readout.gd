extends GutTest

## [CrucibleReadout]: one line per [method ReadoutLines.lines] entry, anchors
## top to bottom in that order, a hovered socket expands its own line only, a
## wedge preview reads "if socketed here", and the full [SpellSections] sit
## behind `ui_more_info` ([member CrucibleReadout.force_more_info] here).

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _SCENE := preload("res://ui/hud/command_tray/bodies/crucible_readout.tscn")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## INT 1000 → 2 infusion slots; every aspect zeroed but poison 40 and curse 10.
func _caster() -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = 1000.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = 40.0
	board.facet(&"curse", StatDef.Role.ASPECT).base_value = 10.0
	return atk


func _plan() -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = _caster()
	plan.set_spell(_VENOM)
	return plan


func _readout(plan: MagicAttackPlan) -> CrucibleReadout:
	var readout: CrucibleReadout = _SCENE.instantiate()
	readout.size = Vector2(320, 0)
	add_child_autofree(readout)
	readout.bind(plan)
	return readout


func test_one_line_per_readout_line_in_order() -> void:
	var plan := _plan()
	plan.set_socket(0, &"curse")
	plan.set_socket(1, &"poison")
	var readout := _readout(plan)
	var expected := ReadoutLines.lines(plan)
	assert_eq(expected.size(), 2, "guard: curse and poison in play")
	assert_eq(plan.infusion.points.keys(), [&"curse", &"poison"], "guard: both socketed")
	var nodes := readout.line_nodes()
	assert_eq(nodes.size(), expected.size())
	for i in mini(nodes.size(), expected.size()):
		assert_eq(nodes[i].main_text(), expected[i].text())
		assert_eq(nodes[i].socket(), expected[i].socket)
	assert_eq(readout.name_text(), _VENOM.name)


func test_lines_follow_the_plan() -> void:
	var plan := _plan()
	var readout := _readout(plan)
	assert_eq(readout.line_nodes().size(), 1, "venom's innate poison alone")
	plan.set_socket(0, &"curse")
	assert_eq(readout.line_nodes().size(), 2, "socketing curse adds its line")


func test_anchors_run_top_to_bottom_in_line_order() -> void:
	var plan := _plan()
	plan.set_socket(0, &"curse")
	plan.set_socket(1, &"poison")
	var readout := _readout(plan)
	await wait_physics_frames(2)
	var a0 := readout.line_anchor(0)
	var a1 := readout.line_anchor(1)
	assert_true(a0.is_finite() and a1.is_finite(), "both sockets have a line")
	assert_lt(a0.y, a1.y, "socket 0's line sits above socket 1's")
	assert_eq(readout.line_anchor(2), Vector2.INF, "no line, no anchor")


func test_hovering_a_socket_expands_only_its_line() -> void:
	var plan := _plan()
	plan.set_socket(0, &"curse")
	plan.set_socket(1, &"poison")
	var readout := _readout(plan)
	readout.set_hovered_socket(1)
	var nodes := readout.line_nodes()
	assert_eq(nodes.size(), 2)
	if nodes.size() != 2:
		return
	assert_false(nodes[0].is_expanded())
	assert_true(nodes[1].is_expanded())
	assert_true(nodes[1].is_highlighted())
	assert_string_contains(nodes[1].detail_text(), InfusionExchange.line(_VENOM, &"poison", 40))
	readout.set_hovered_socket(-1)
	assert_false(readout.line_nodes()[1].is_expanded(), "unhover collapses")


func test_a_wedge_preview_reads_the_line_as_if_socketed() -> void:
	var plan := _plan()
	var readout := _readout(plan)
	readout.preview_wedge(0, &"poison")
	var expected := ReadoutLines.preview(plan, 0, &"poison")
	var nodes := readout.line_nodes()
	assert_eq(nodes.size(), 1)
	if nodes.size() == 1:
		assert_eq(nodes[0].main_text(), expected[0].text(), "the previewed line")
		assert_true(nodes[0].is_highlighted())
	assert_eq(plan.infusion.points.size(), 0, "a preview never writes the plan")
	readout.clear_preview()
	assert_eq(readout.line_nodes()[0].main_text(), ReadoutLines.lines(plan)[0].text())


func test_sections_sit_behind_more_info() -> void:
	var readout := _readout(_plan())
	assert_false(readout.is_more_info(), "at rest, no sections")
	readout.force_more_info = true
	assert_true(readout.is_more_info(), "more info shows the sections")
