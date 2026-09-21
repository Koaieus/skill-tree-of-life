extends GutTest

## #957 — a volley is N typed arrows: `max_n()` = min(stock, Σ shots_left over
## reaching leaves); the schedule is WAVE-MAJOR (every reaching leaf with a
## shot left fires once per wave, nearest-first, until N); ammo types are
## assigned along that schedule in roster `AmmoType.order` (armour-breaking /
## poison first, the base arrow last); and a mirror rebuilding the plan from
## its wire dict produces the identical schedule.
##
## Fixture: hub `_mid`(200,0) with three reaching leaves around the target
## (450,0) — near (400,0) d=50, mid_leaf (450,150) d=150, far (450,-300) d=300.
## Shots left 5/5, 5/5, 4/5 (the far leaf already fired once this turn);
## quiver 15 arrow + 5 poison = 20.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

const _POISON := &"poison"
const _ARROW := &"arrow"

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _mid: SkillNode
var _near: SkillNode
var _mid_leaf: SkillNode
var _far: SkillNode
var _target: SkillNode


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _leaf(pos: Vector2) -> SkillNode:
	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = pos
	_graph.add_skill_node(leaf)
	_graph.add_edge(leaf, _mid)
	return leaf


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_mid = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_mid.position = Vector2(200, 0)
	_graph.add_skill_node(_mid)
	_near = _leaf(Vector2(400, 0))
	_mid_leaf = _leaf(Vector2(450, 150))
	_far = _leaf(Vector2(450, -300))
	_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_target.position = Vector2(450, 0)
	_graph.add_skill_node(_target)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	# Flat board: kill-sized-volley fixture, tuned CON must not ride in on the target's HP.
	_attacker.stat_board = TestBoards.flat_entity_board()
	_graph.entities_container.add_child(_attacker)
	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = TestBoards.flat_entity_board()
	_graph.entities_container.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	for n in [_mid, _near, _mid_leaf, _far]:
		_alloc.force_allocate(_attacker, n)
	_alloc.force_allocate(_hostile, _target)
	autofree(_attacker)
	autofree(_hostile)

	for n in [_near, _mid_leaf, _far]:
		_set_stat(n, &"range", 1000.0)
		_set_stat(n, &"ranged_damage", 3.0)
	_far.mark_shot_fired(1)
	_attacker.stat_board.arrows.add(_ARROW, 15)
	_attacker.stat_board.arrows.add(_POISON, 5)


func _plan() -> RangedAttackPlan:
	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	p._on_node_left_clicked(_target)
	return p


func _leaf_counts(schedule: Array) -> Dictionary:
	var counts := {}
	for shot in schedule:
		counts[shot.firing_node] = counts.get(shot.firing_node, 0) + 1
	return counts


func test_fixture_shots_left_and_stock() -> void:
	assert_eq(_near.shots_left(), 5)
	assert_eq(_far.shots_left(), 4)
	assert_eq(roundi(_attacker.stat_board.arrows.current), 20)


func test_max_n_is_min_of_stock_and_shots_left_over_reaching_leaves() -> void:
	var p := _plan()
	assert_eq(p.max_n(), 14, "5 + 5 + 4 shots left < 20 stock")
	_attacker.stat_board.arrows.take(_ARROW, 10)
	assert_eq(p.max_n(), 10, "stock 10 caps the volley below the shot budget")


func test_default_composition_is_all_base_at_max_n() -> void:
	var p := _plan()
	assert_eq(p.n(), 14, "bare input: N = max")
	assert_eq(p.effective_ammo_counts(), {_ARROW: 14})


func test_composition_yields_wave_major_schedule_with_types_in_roster_order() -> void:
	var p := _plan()
	p.ammo_counts = {_POISON: 2, _ARROW: 5}
	assert_eq(p.n(), 7)
	var schedule := p.get_firing_schedule()
	assert_eq(schedule.size(), 7)
	# Wave-major, nearest-first inside each wave: near, mid_leaf, far | near,
	# mid_leaf, far | near.
	var expected: Array[SkillNode] = [_near, _mid_leaf, _far, _near, _mid_leaf, _far, _near]
	for i in schedule.size():
		assert_eq(schedule[i].firing_node, expected[i], "shot %d fires from the wave-major leaf" % i)
		assert_eq(schedule[i].wave, i / 3, "shot %d sits in wave %d" % [i, i / 3])
	var counts := _leaf_counts(schedule)
	assert_eq(counts[_near], 3)
	assert_eq(counts[_mid_leaf], 2)
	assert_eq(counts[_far], 2)
	assert_eq(schedule[0].ammo_type.id, _POISON, "poison (order 80) is assigned first")
	assert_eq(schedule[1].ammo_type.id, _POISON)
	for i in range(2, 7):
		assert_eq(schedule[i].ammo_type.id, _ARROW, "the base arrow fills the rest")


func test_resolve_lands_poison_first_in_structural_key_order_and_costs_no_ap() -> void:
	var p := _plan()
	p.ammo_counts = {_POISON: 2, _ARROW: 5}
	var outcome := p.resolve()
	# One DAMAGE hit per arrow; a poison arrow also emits its status hit (#495).
	var arrows: Array = outcome.hits.filter(func(h: HitInstance) -> bool:
		return h.kind == HitInstance.Kind.DAMAGE)
	assert_eq(arrows.size(), 7)
	assert_eq(outcome.hits.size(), 9, "2 poison arrows carry 2 status hits alongside")
	assert_eq(outcome.ap_cost, 0, "firing costs 0 AP")
	var ordered: Array = arrows.duplicate()
	ordered.sort_custom(func(a: HitInstance, b: HitInstance) -> bool:
		return a.structural_key < b.structural_key)
	assert_eq(ordered[0].ammo_type.id, _POISON)
	assert_eq(ordered[1].ammo_type.id, _POISON)
	assert_eq(ordered[0].origin, _near, "wave 0's nearest leaf lands first")
	assert_eq(ordered[6].origin, _near, "wave 2's lone shot lands last")
	for h in outcome.hits:
		assert_between(h.structural_key, 0.0, 1.0, "RAMP keys stay in [0, 1]")
	# Same key across a wave boundary is broken by original index, so a later
	# wave never lands BEFORE an earlier one.
	for i in range(1, 7):
		assert_true(ordered[i].structural_key >= ordered[i - 1].structural_key)


func test_mirror_plan_from_wire_dict_produces_the_identical_schedule() -> void:
	var p := _plan()
	p.ammo_counts = {_POISON: 2, _ARROW: 5}
	var d := p.to_dict(_graph)
	assert_eq(d.get("ammo_counts"), {_POISON: 2, _ARROW: 5})
	var mirror := RangedAttackPlan.from_dict(d, _graph)
	autofree(mirror)
	var a := p.get_firing_schedule()
	var b := mirror.get_firing_schedule()
	assert_eq(b.size(), a.size())
	for i in a.size():
		assert_eq(b[i].firing_node, a[i].firing_node)
		assert_eq(b[i].wave, a[i].wave)
		assert_eq(b[i].ammo_type.id, a[i].ammo_type.id)


func test_validate_third_state() -> void:
	var p := _plan()
	p.ammo_counts = {_POISON: 6}
	assert_false(p.validate().is_empty(), "a count above its bin is refused")
	p.ammo_counts = {_ARROW: 15}
	assert_false(p.validate().is_empty(), "N above the shot budget is refused")
	p.ammo_counts = {}
	_attacker.stat_board.arrows.take(_ARROW, 15)
	_attacker.stat_board.arrows.take(_POISON, 5)
	assert_has(p.validate(), RangedAttackPlan.ERR_NO_AMMO)
	_attacker.stat_board.arrows.add(_ARROW, 5)
	for n in [_near, _mid_leaf, _far]:
		n.mark_shot_fired(5)
	assert_has(p.validate(), RangedAttackPlan.ERR_NO_SHOTS)
	_near.shots_fired_this_turn = 0
	assert_true(p.validate().is_empty())
	_attacker.volleys_launched_this_turn = int(_attacker.stat_board.volleys_per_turn.value)
	assert_has(p.validate(), RangedAttackPlan.ERR_VOLLEY_LIMIT)


# ── Consumption at commit (#957 acceptance 2) ────────────────────────────

func _battle_system() -> BattleSystem:
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)
	var vfx := AttackVFX.new()
	add_child_autofree(vfx)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = _alloc
	bs.graph = _graph
	bs.attack_vfx = vfx
	add_child_autofree(bs)
	return bs


func test_launch_consumes_bins_leaf_shots_and_a_volley_slot_but_no_ap() -> void:
	_attacker.stat_board.action_points.base_value = 2.0
	_attacker.stat_board.action_points.current = 2.0
	var bs := _battle_system()
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(_target)
	plan.ammo_counts = {_POISON: 2, _ARROW: 5}
	assert_true(plan.is_valid(), str(plan.validate()))

	await bs.launch_attack()

	var quiver: Quiver = _attacker.stat_board.arrows
	assert_eq(quiver.stock_of(_POISON), 3, "2 poison spent")
	assert_eq(quiver.stock_of(_ARROW), 10, "5 arrows spent")
	assert_eq(roundi(quiver.current), 13)
	assert_eq(_near.shots_fired_this_turn, 3)
	assert_eq(_mid_leaf.shots_fired_this_turn, 2)
	assert_eq(_far.shots_fired_this_turn, 3, "1 before the volley + 2 fired")
	assert_eq(_attacker.volleys_launched_this_turn, 1)
	assert_eq(_attacker.stat_board.action_points.available(), 2, "firing costs no AP")
	for leaf in [_near, _mid_leaf, _far]:
		assert_true(_attacker._fired_nodes_this_turn.has(leaf), "%s is in the firer's reset set" % leaf.name)


func test_volley_limit_reached_fails_validate_with_the_volleys_reason() -> void:
	# A sturdy target: five 1-arrow volleys must not kill it on the way.
	_set_stat(_target, &"node_health", 1000.0)
	var bs := _battle_system()
	var limit := int(_attacker.stat_board.volleys_per_turn.value)
	assert_gt(limit, 0, "precondition: the board grants volleys")
	for i in limit:
		bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
		var plan := bs.attack_plan as RangedAttackPlan
		plan._on_node_left_clicked(_target)
		plan.ammo_counts = {_ARROW: 1}
		assert_true(plan.is_valid(), "volley %d: %s" % [i, str(plan.validate())])
		await bs.launch_attack()
	assert_eq(_attacker.volleys_launched_this_turn, limit)
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var extra := bs.attack_plan as RangedAttackPlan
	extra._on_node_left_clicked(_target)
	extra.ammo_counts = {_ARROW: 1}
	assert_has(extra.validate(), RangedAttackPlan.ERR_VOLLEY_LIMIT)


func test_a_target_that_dies_mid_volley_still_consumes_every_arrow() -> void:
	# 3 dmg/leaf into the default 10 node_health: the 4th shot kills, shots
	# 5..7 are vetoed duds — and still paid for.
	var bs := _battle_system()
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(_target)
	plan.ammo_counts = {_ARROW: 7}
	assert_true(plan.is_valid(), str(plan.validate()))
	var stock_before := roundi(_attacker.stat_board.arrows.current)
	await bs.launch_attack()
	assert_ne(_target.owned_by, _hostile, "precondition: the target died")
	assert_eq(roundi(_attacker.stat_board.arrows.current), stock_before - 7,
			"duds consume — a shot fired is a shot fired")
	assert_eq(_near.shots_fired_this_turn + _mid_leaf.shots_fired_this_turn
			+ (_far.shots_fired_this_turn - 1), 7)
