extends GutTest

## `midas_mark_addon.tscn` — Greed × Addon. On the map it grants its owner +1
## `greed_aspect` and, at the owner's turn start, tops its allocated carrier's
## Greed up by `gain_flat + gain_per_level × level` toward
## `cap_per_level × level`, never past it; a temporary copy never runs that
## hook. On a blade every contact lands Greed folded through
## `greed_stacks_per_hit`. Gain and cap are read off the scene's exports,
## never literals.
##
## Fixture: test_doombrand_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc — plus a loose "Hoard" node the attacker
## allocates to carry a mark off the blade.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _MIDAS_SCENE := preload("res://skill_node/addons/defs/midas_mark_addon.tscn")
const _GREED := preload("res://effects/status/greed.tres")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _plate: SkillNode
var _hoard: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity() -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	# Past the first-turn upkeep skip, so one begin_turn() runs the upkeep.
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"midas_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_hoard = _spawn("Hoard", Vector2(-_SPACING, -_SPACING * 3.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_graph.add_edge(_pivot, _hoard)
	_plate = _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	var camp := _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_graph.add_edge(camp, _plate)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	for n in [_pivot, _mid, _tip, _hoard]:
		_alloc.force_allocate(_attacker, n)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, camp)
	_defender.core_location = camp
	_alloc.force_allocate(_defender, _plate)
	_mid.add_child(_CLAMP_SCENE.instantiate())


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mark(node: SkillNode, temporary := false) -> MidasMarkAddon:
	var addon := _MIDAS_SCENE.instantiate() as MidasMarkAddon
	addon.is_temporary = temporary
	node.add_child(addon)
	return addon


func _raise(node: SkillNode, level: int) -> void:
	node.stake_level = maxi(node.stake_level, level)
	_alloc.force_fill(node, level)


func _greed(node: SkillNode) -> float:
	return node.get_combat().get_status_power(_GREED.id)


## The authored exports, off a fresh instance — what the formulas read.
func _exports() -> MidasMarkAddon:
	var addon: MidasMarkAddon = autofree(_MIDAS_SCENE.instantiate())
	return addon


func _gain(level: int) -> float:
	var e := _exports()
	return float(e.gain_flat + e.gain_per_level * level)


func _cap(level: int) -> float:
	return float(_exports().cap_per_level * level)


# ── map face: turn-start top-up ─────────────────────────────────────────────

func test_scene_root_is_a_midas_mark_with_greed() -> void:
	var e := _exports()
	assert_true(e is MidasMarkAddon)
	assert_eq(e.greed_status, _GREED, "the mark grows Greed")


func test_an_allocated_carrier_gains_per_turn_up_to_its_cap_at_every_level() -> void:
	for level in [1, 2, 3]:
		var node := _spawn("Hoard%d" % level, Vector2(-_SPACING * level, _SPACING * 6.0))
		_graph.add_edge(_pivot, node)
		_alloc.force_allocate(_attacker, node)
		_raise(node, level)
		_mark(node)
		await get_tree().process_frame
		assert_eq(node.allocation_level, level, "arranged at %d/X" % level)
		assert_gt(_gain(level), 0.0, "precondition: a mark gains at %d/X" % level)
		var expected := 0.0
		# Enough turns to reach the cap, then two more to prove it holds.
		var turns := int(ceilf(_cap(level) / _gain(level))) + 2
		for t in turns:
			_attacker.begin_turn()
			expected = minf(expected + _gain(level), _cap(level))
			assert_eq(_greed(node), expected, "%d/X turn %d" % [level, t + 1])
		assert_eq(_greed(node), _cap(level), "%d/X holds at its cap" % level)
		node.get_combat().remove_status(_GREED.id)


func test_a_spent_stack_refills_next_turn() -> void:
	_raise(_hoard, 2)
	_mark(_hoard)
	await get_tree().process_frame
	for t in int(ceilf(_cap(2) / _gain(2))):
		_attacker.begin_turn()
	assert_eq(_greed(_hoard), _cap(2), "arranged at the cap")
	_hoard.get_combat().adjust_status_power(_GREED, -1.0)
	assert_eq(_greed(_hoard), _cap(2) - 1.0, "a hit spent one")
	_attacker.begin_turn()
	assert_eq(_greed(_hoard), _cap(2), "refilled to the cap, not past it")


func test_an_unallocated_carrier_gains_nothing() -> void:
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 8.0))
	var addon := _mark(loose)
	await get_tree().process_frame
	addon.on_turn_start()
	assert_eq(_greed(loose), 0.0, "only an allocated carrier gathers Greed")


func test_a_temporary_mark_never_runs_the_turn_start_hook() -> void:
	_raise(_hoard, 2)
	_mark(_hoard, true)
	await get_tree().process_frame
	_attacker.begin_turn()
	assert_eq(_greed(_hoard), 0.0, "a temp mark is a blade copy only")


# ── map face: the aspect ────────────────────────────────────────────────────

func test_allocating_a_midas_node_grants_the_owner_greed_aspect() -> void:
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 8.0))
	_graph.add_edge(_pivot, loose)
	var before: float = _attacker.stat_board.get_value(&"greed_aspect")
	_mark(loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"greed_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"greed_aspect"), before + 1.0)


func test_a_temp_midas_costs_2_blade_size_and_1_greed_aspect() -> void:
	assert_true(SkillNodeAddon.temp_placeable_of(_MIDAS_SCENE))
	var costs := SkillNodeAddon.temp_costs_of(_MIDAS_SCENE)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"greed_aspect", 0), 1)


# ── blade face: the Greed rider ─────────────────────────────────────────────

func _plan() -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_mid, _tip]
	return plan


## The Greed stacks the outcome's first landed Greed carried.
func _landed_greed(outcome: AttackOutcome) -> float:
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _GREED:
			return status.power
	assert_true(false, "the midas vertex lands Greed on its contact")
	return -1.0


func _swing() -> float:
	var shadow := CombatWorld.shadow()
	var greed := _landed_greed(_plan().resolve_against(shadow))
	shadow.free_shadow()
	return greed


func test_a_midas_contact_lands_greed() -> void:
	_mark(_tip)
	await _settle()
	assert_gt(_swing(), 0.0)


func test_greed_stacks_per_hit_folds_into_the_rider() -> void:
	_mark(_tip)
	await _settle()
	var plain := _swing()
	var more := StatModifier.new()
	more.stat_id = &"greed_stacks_per_hit"
	more.value = 2.0
	_attacker.stat_board.add_modifier(more)
	await _settle()
	assert_eq(_swing(), plain + 2.0, "the attacker's +2 folds into the rider")


func test_the_marks_local_stacks_per_hit_scales_with_level() -> void:
	_mark(_tip)
	await _settle()
	var at_one := _swing()
	_raise(_tip, 2)
	await _settle()
	assert_gt(_swing(), at_one, "a 2/X mark lands more Greed than a 1/X one")
