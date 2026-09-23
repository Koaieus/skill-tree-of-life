extends GutTest

## #954 — the ranged command-tray body is the Quiver's view: one notched
## volley bar (N / max, wave boundaries as notches, typed segments), an ammo
## card per owned type with a stepper on each special, base arrows as the
## remainder, sticky special counts across target picks, and the reload row
## showing the projected yield. No kills text anywhere (owner: "TMI").
##
## Fixture (test_ranged_volley_composition's world): core `_mid`(200,0) with
## three reaching leaves around target T(450,0) — near (400,0), mid_leaf
## (450,150), far (450,-300); shots left 5/5, 5/5, 4/5 (far fired once);
## bins {arrow: 9, poison: 2} → max 11, notches 3, 6, 9. A second hostile
## target T2 sits at (500,0) for the sticky-count case.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _WATCHTOWER_SCENE := preload("res://skill_node/addons/watchtower_addon.tscn")
const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/ranged_body.tscn")

const _POISON := &"poison"
const _ARROW := &"arrow"

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _battle: BattleSystem
var _attacker: Entity
var _hostile: Entity
var _mid: SkillNode
var _near: SkillNode
var _mid_leaf: SkillNode
var _far: SkillNode
var _target: SkillNode
var _target2: SkillNode
var _plan: RangedAttackPlan
var _body: RangedBody
var _base_range: float


## ADD_BASE, not SET: a Watchtower's own range bonus must still stack on top.
func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	node.add_local_modifier(m)


func _node(pos: Vector2) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.position = pos
	_graph.add_skill_node(n)
	return n


func _leaf(pos: Vector2) -> SkillNode:
	var leaf := _node(pos)
	_graph.add_edge(leaf, _mid)
	return leaf


func _entity(faction: Resource) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	autofree(e)
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_mid = _node(Vector2(200, 0))
	_near = _leaf(Vector2(400, 0))
	_mid_leaf = _leaf(Vector2(450, 150))
	_far = _leaf(Vector2(450, -300))
	_target = _node(Vector2(450, 0))
	_target2 = _node(Vector2(500, 0))
	_graph.add_edge(_target, _target2)

	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_attacker = _entity(_PLAYER_FACTION)
	_hostile = _entity(_NPC_FACTION)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	_alloc.turn_manager = _tm
	add_child_autofree(_alloc)
	_attacker.core_location = _mid
	for n in [_mid, _near, _mid_leaf, _far]:
		_alloc.force_allocate(_attacker, n)
	_hostile.core_location = _target
	_alloc.force_allocate(_hostile, _target)
	_alloc.force_allocate(_hostile, _target2)
	for n in [_near, _mid_leaf, _far]:
		_set_stat(n, &"range", 1000.0)
		_set_stat(n, &"ranged_damage", 3.0)
	_base_range = float(_near.get_local_value(&"range"))
	_far.mark_shot_fired(1)
	_attacker.stat_board.arrows.add(_ARROW, 9)
	_attacker.stat_board.arrows.add(_POISON, 2)
	# Turn start captures the reload producer set (the three leaves ∪ core).
	_tm.start_turn(_attacker)
	_attacker.stat_board.action_points.restore_to_full()

	_battle = autofree(BattleSystem.new())
	add_child(_battle)
	_plan = RangedAttackPlan.new()
	autofree(_plan)
	_plan.attacker = _attacker
	_battle.attack_plan = _plan

	_body = _BODY_SCENE.instantiate() as RangedBody
	add_child_autofree(_body)
	_body.bind(_attacker, _battle, null)
	_plan.handle_left_click(_target)


func _per_leaf() -> int:
	return int(_attacker.stat_board.arrows_per_reload.get_value())


func _bar() -> VolleyBar:
	return _body.get_node("%VolleyBar") as VolleyBar


func _reload_button() -> Button:
	return _body.get_node("%ReloadButton") as Button


func _card(type_id: StringName) -> AmmoCard:
	for c in _body.cards():
		if c.type.id == type_id:
			return c
	return null


func test_bar_max_and_default_n_and_wave_notches() -> void:
	assert_eq(_body.max_n(), 11, "min(stock 11, shots 5+5+4)")
	assert_eq(_body.n(), 11, "N defaults to max, not kill-snapped")
	assert_eq(_bar().max_n, 11)
	assert_eq(_bar().n, 11)
	assert_eq(Array(_bar().notches), [3, 6, 9], "wave boundaries below max")
	assert_eq(_plan.ammo_counts, {_ARROW: 9, _POISON: 2}, "the body writes the explicit composition")


## N = max = stock (11) means every arrow fires, so the default already reads
## {arrow 9, poison 2}. Lowering a special the base bin cannot absorb lowers
## N with it (owner: base is the remainder, never a control); raising one at
## a fixed N carves it out of the base; scrolling N re-derives the base.
func test_stepping_poison_and_scrolling_n_down_re_derives_base() -> void:
	_body.set_special(_POISON, 1)
	assert_eq(_plan.ammo_counts, {_ARROW: 9, _POISON: 1}, "base is bin-capped at 9 → N follows down to 10")
	assert_eq(_body.n(), 10)
	_body.step_special(_POISON, 1)
	assert_eq(_plan.ammo_counts, {_POISON: 2, _ARROW: 8}, "at fixed N 10 the extra poison carves out of base")
	_body.reset_n_to_max()
	assert_eq(_body.n(), 11)
	assert_eq(_plan.ammo_counts, {_POISON: 2, _ARROW: 9})
	_body.set_n(4)
	assert_eq(_plan.ammo_counts, {_POISON: 2, _ARROW: 2}, "N 4 with 2 poison → 2 base")
	assert_eq(_body.n(), 4)
	_body.set_n(1)
	assert_eq(_body.n(), 2, "specials exceed N → N grows to fit")
	assert_eq(_plan.ammo_counts, {_POISON: 2})
	_body.set_special(_POISON, 0)
	assert_eq(_plan.ammo_counts, {_ARROW: 2}, "no poison at N 2 → 2 base")
	_body.reset_n_to_max()
	assert_eq(_plan.ammo_counts, {_POISON: 2, _ARROW: 9}, "max fires everything again")


func test_special_count_is_sticky_across_target_picks_and_clamps_to_bin() -> void:
	_body.set_special(_POISON, 2)
	_body.set_n(4)
	_plan.handle_left_click(_target2)
	assert_eq(_body.n(), 11, "a new target rebuilds at N = max")
	assert_eq(_plan.ammo_counts, {_POISON: 2, _ARROW: 9}, "poison stays 2 while the bin has 2")
	_attacker.stat_board.arrows.take(_POISON, 1)
	_plan.handle_left_click(_target)
	assert_eq(_plan.ammo_counts, {_POISON: 1, _ARROW: 9}, "clamped to the bin once it has 1")


func test_reload_row_shows_projected_yield_and_ap() -> void:
	var expected := 4 * _per_leaf()  # three leaves + core, all level 1
	assert_eq(expected, 8, "authored arrows_per_reload is 2 → +8")
	assert_eq(_reload_button().text, "⟳ Reload  +%d  −1 AP" % expected)
	assert_false(_reload_button().disabled, "enabled with AP to spend — the stock Button look is not a disabled state")


func test_cards_show_stock_and_gain_per_owned_type() -> void:
	var arrow := _card(_ARROW)
	var poison := _card(_POISON)
	assert_not_null(arrow, "base card")
	assert_not_null(poison, "poison card")
	assert_eq(arrow.stock, 9)
	assert_eq(arrow.gain, 4 * _per_leaf())
	assert_eq(poison.stock, 2)
	assert_eq(poison.gain, int(_attacker.stat_board.poison_arrows_per_reload.get_value()))
	assert_false(arrow.has_stepper(), "base arrows are not a control")
	assert_true(poison.has_stepper(), "specials get a stepper")


func test_hot_seat_rebind_swaps_the_roster() -> void:
	var other := _entity(_PLAYER_FACTION)
	other.stat_board.arrows.add(_ARROW, 3)
	_body.teardown()
	_body.bind(other, _battle, null)
	var ids: Array = []
	for c in _body.cards():
		ids.append(c.type.id)
	assert_eq(ids, [_ARROW], "the other player's quiver: base only")


func test_per_leaf_readout_reads_the_plan_not_the_board() -> void:
	var before := _body.leaf_readouts()
	assert_eq(before.size(), 3, "three reaching leaves")
	_near.add_child(_WATCHTOWER_SCENE.instantiate())
	_plan.state_changed.emit()
	var after := _body.leaf_readouts()
	var by_node := {}
	for r in after:
		by_node[r.node] = r
	assert_gt(float(by_node[_near].range), _base_range, "Watchtower extends near's range")
	assert_eq(float(by_node[_far].range), _base_range, "and not far's")
	assert_eq(float(by_node[_mid_leaf].range), _base_range, "nor mid_leaf's")
	assert_eq(int(by_node[_near].shots), 4, "near fires 4 of 11 (waves 0..3)")


func test_no_kill_readout_exists() -> void:
	for label in _body.find_children("*", "Label", true, false):
		var t := (label as Label).text.to_lower()
		assert_false(t.contains("kill"), "no kills text in the body: '%s'" % t)


## The body must fit the tray slot by construction (the #753 lesson): two
## cards, a bar and three buttons stay inside the magic body's budget.
func test_body_stays_inside_the_tray_budget() -> void:
	_body.size = Vector2(930.0, _body.get_combined_minimum_size().y)
	await get_tree().process_frame
	await get_tree().process_frame
	var min_size := _body.get_combined_minimum_size()
	gut.p("ranged body min size = %s" % min_size)
	assert_lt(min_size.x, 891.0, "min width inside the tray slot")
	assert_lt(min_size.y, 231.0, "min height inside the tray budget")


func _set_local(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## #1036: at a sensed-only target only scouts fly, so the composer reads every
## other bin as empty — the default composition is all the scouts in stock and
## validates, rather than opening on the mix error.
func test_a_sensed_target_composes_scouts_only() -> void:
	_attacker.stat_board.arrows.add(&"scout", 2)
	_graph.add_edge(_near, _target)
	for n in [_mid, _near, _mid_leaf, _far]:
		_set_local(n, &"vision_range", 10.0)
		_set_local(n, &"sensor_range", 0.0)
	_set_local(_near, &"sensor_range", 1.0)
	var vision := VisionSystem.new()
	vision.graph = _graph
	vision.viewers = [_attacker]
	add_child_autofree(vision)
	await get_tree().process_frame
	vision._recompute()
	assert_true(vision.is_sensed(_target) and not vision.is_visible(_target), "fixture: target is sensed-only")
	_body.set_special(_POISON, 1)
	assert_true(_plan.ammo_counts.has(_POISON) and _plan.ammo_counts.has(_ARROW), "control: without the viewer fog poison and base fire")
	_plan.viewer_vision = vision
	_plan.reset()
	_plan.handle_left_click(_target)
	assert_true(_plan.is_scout_shot(), "fixture: the plan sees a scout shot")
	assert_eq(_plan.ammo_counts, {&"scout": 2}, "scouts only, poison and base forced to 0")
	assert_eq(_plan.validate(), [] as Array[String], "the default composition validates")
	_body.step_special(_POISON, 1)
	assert_eq(_plan.ammo_counts, {&"scout": 2}, "a poison step is clamped back to 0 into fog")
