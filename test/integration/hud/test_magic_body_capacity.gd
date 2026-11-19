extends GutTest

## The composed magic tray body over the cap in force (ADR 0089): the tally's
## cap reads [method MagicAttackPlan.capacity], a "back to base" control shows
## while the aspects sit above the base cap and trims them there, and a notice
## line follows a pick that trimmed the loadout.
##
## Board: ATK owns n0 - n1 - n2 (owned degrees 1 / 2 / 1); hostile targets t3
## (reached by n1 and n2), t4 (n1 only) and t5 (n0 only). A min_degree-1 spell:
## n0 and n2 carry the base cap B, n1 carries one degree more.

const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")
const _B := 4.0
const _K := 3

var _host: SubViewport
var _body: MagicBody
var _ctl: PlayerInputController
var _n: Array[SkillNode] = []


func after_each() -> void:
	if is_instance_valid(_body) and _ctl != null:
		_body.teardown()
	_ctl = null


func _spell() -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Test Bolt"
	spell.infusion_capacity = _B
	spell.infusion_capacity_per_degree = _K
	spell.min_degree = 1
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.HOSTILE
	var f := HopRangeFinder.new()
	f.max_hops = 0
	t.range_finder = f
	spell.targeting = t
	return spell


func _arm() -> void:
	_host = SubViewport.new()
	_host.size = Vector2i(1000, 400)
	add_child_autofree(_host)
	_body = _BODY_SCENE.instantiate() as MagicBody
	_host.add_child(_body)
	var h := SpellTestHelper.new()
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3], [1, 3], [1, 4], [0, 5]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var def := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, atk, [0, 1, 2])
	h.assign_owner(graph, def, [3, 4, 5])
	_n.assign(graph.get_skill_nodes())
	var board := atk.stat_board
	board.intelligence.base_value = 1000.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	for id in [&"poison", &"curse"]:
		board.facet(id, StatDef.Role.COUNT).base_value = 50.0
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(atk)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.graph = graph
	add_child_autofree(bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = graph
	_ctl.turn_manager = tm
	_ctl.battle_system = bs
	_ctl.player = atk
	add_child_autofree(_ctl)
	_body.bind(atk, bs, _ctl)
	_ctl.armed_stack.select_spell(atk, _spell())
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	await wait_frames(2)


func _plan() -> MagicAttackPlan:
	return _ctl.armed_stack.attack_plan() as MagicAttackPlan


func _control(unique: String) -> Control:
	return _body.get_node_or_null(unique) as Control


func test_the_base_reset_shows_above_base_and_trims_to_it() -> void:
	await _arm()
	var plan := _plan()
	var reset := _control("%BaseCapReset") as Button
	assert_not_null(reset)
	if reset == null:
		return
	var base := plan.base_capacity()
	plan.set_infusion(&"poison", base)
	assert_false(reset.visible, "at the base cap: hidden")
	plan.set_socket(0, &"poison")
	assert_gt(plan.infusion.total_points(), base, "guard: filled past base to the best caster's cap")
	assert_true(reset.visible, "above the base cap: shown")
	reset.pressed.emit()
	assert_lte(plan.infusion.total_points(), base)
	assert_eq(plan.aspect_overrun(), 0)
	assert_false(reset.visible, "back at base: hidden again")


func test_the_notice_follows_a_trimming_pick_only() -> void:
	await _arm()
	var plan := _plan()
	var notice := _control("%TrimNotice")
	assert_not_null(notice)
	if notice == null:
		return
	assert_false(notice.visible, "nothing trimmed yet")
	plan.set_infusion(&"poison", plan.spell.capacity_at(plan.spell.min_degree + 1))
	assert_true(plan.set_target(_n[5]), "a base-only target, below the loadout")
	assert_true(notice.visible, "the trimming pick shows the notice")
	plan.set_target(_n[4])
	assert_false(notice.visible, "a pick that trims nothing hides it")


func test_the_tally_cap_reads_the_cap_in_force() -> void:
	await _arm()
	var plan := _plan()
	var tally := _control("%Tally") as Label
	plan.set_target(_n[4])
	assert_ne(plan.capacity(), plan.base_capacity(), "guard: the best caster reaching t4 is above min_degree")
	assert_eq(tally.text, "%d / %d" % [plan.infusion.total_points(), plan.capacity()])
	plan.set_target(_n[5])
	assert_eq(tally.text, "%d / %d" % [plan.infusion.total_points(), plan.base_capacity()])
