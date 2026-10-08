extends GutTest

## `compromiser_addon.tscn` — Corruption × Addon. On the map it grants its
## owner +1 `corruption_aspect`; on a blade its vertex lands a flat 1
## corruption per contact at every allocation level (no ladder, no 3/X
## multiplier — corruption's per-node budget is its degree), folded with the
## attacker's `corruption_stacks_per_hit` as every rider is. A temp placement
## lands the same, costs 2 blade size + 1 `corruption_aspect`, and never
## raises the aspect it spends.
##
## Fixture: test_addon_on_hit.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _COMPROMISER_SCENE := preload("res://skill_node/addons/defs/compromiser_addon.tscn")
const _CORRUPTION := preload("res://effects/status/corruption.tres")
## A rigid spine (mid welded) traces the nominal radius the plate sits on.
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
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


func _sharpen(node: SkillNode, amount: float) -> void:
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = amount
	node.add_local_modifier(sharp)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"compromiser_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_plate = _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	# The plate is territory, not the core: a cracked core would fall the
	# status through to the entity host and hide the node landing.
	var camp := _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_graph.add_edge(camp, _plate)
	_alloc.force_allocate(_defender, camp)
	_defender.core_location = camp
	_alloc.force_allocate(_defender, _plate)
	_sharpen(_tip, 20.0)
	_mid.add_child(_CLAMP_SCENE.instantiate())


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _plan() -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_mid, _tip]
	return plan


func _attach(node: SkillNode) -> SkillNodeAddon:
	var addon := _COMPROMISER_SCENE.instantiate() as SkillNodeAddon
	node.add_child(addon)
	return addon


## Stakes [param node] to [param level] and fills it there through the
## AllocationSystem — the real allocation path, never a written level.
func _fill(node: SkillNode, level: int) -> void:
	node.stake_level = level
	_alloc.force_fill(node, level)


## The corruption stacks the outcome's first landed corruption carried.
func _corruption(outcome: AttackOutcome) -> float:
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _CORRUPTION:
			return status.power
	assert_true(false, "the compromiser vertex lands corruption on its contact")
	return -1.0


# ── blade face: a flat 1 per contact ────────────────────────────────────────

func test_a_compromiser_on_a_1_of_x_blade_node_lands_1_stack() -> void:
	_attach(_tip)
	await _settle()
	assert_eq(_corruption(_plan().resolve_against(CombatWorld.live())), 1.0)


func test_a_compromiser_on_a_2_of_x_blade_node_still_lands_1_stack() -> void:
	_fill(_tip, 2)
	_attach(_tip)
	await _settle()
	assert_eq(_corruption(_plan().resolve_against(CombatWorld.live())), 1.0,
			"no allocation ladder")


func test_a_compromiser_on_a_3_of_x_blade_node_still_lands_1_stack() -> void:
	_fill(_tip, 3)
	_attach(_tip)
	await _settle()
	assert_eq(_corruption(_plan().resolve_against(CombatWorld.live())), 1.0,
			"no 3/X multiplier")


func test_the_attackers_corruption_stacks_per_hit_folds_into_the_rider() -> void:
	var more := StatModifier.new()
	more.stat_id = &"corruption_stacks_per_hit"
	more.value = 2.0
	_attacker.stat_board.add_modifier(more)
	_attach(_tip)
	await _settle()
	assert_eq(_corruption(_plan().resolve_against(CombatWorld.live())), 3.0,
			"1 authored + 2 from the attacker's board")


# ── temp face ───────────────────────────────────────────────────────────────

func test_a_temp_compromiser_lands_the_same_1_per_contact() -> void:
	_attacker.stat_board.corruption_aspect.base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_tip, _COMPROMISER_SCENE), "fits the budget")
	await _settle()
	assert_eq(_corruption(plan.resolve_against(CombatWorld.live())), 1.0)


func test_a_temp_compromiser_costs_2_blade_size_and_1_corruption_aspect() -> void:
	var costs := SkillNodeAddon.temp_costs_of(_COMPROMISER_SCENE)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"corruption_aspect", 0), 1)


func test_corruption_aspect_caps_temp_compromisers_per_swing() -> void:
	_attacker.stat_board.corruption_aspect.base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_mid, _COMPROMISER_SCENE), "the first fits")
	assert_eq(plan.currency_remaining(&"corruption_aspect"), 0)
	assert_false(plan.can_apply_temp_upgrade(_tip, _COMPROMISER_SCENE), "one past the aspect")
	assert_eq(plan.temp_upgrade_denial_reason(_tip, _COMPROMISER_SCENE),
			"temp_upgrade_denied_aspect")


# ── map face: +1 corruption_aspect to the allocator ─────────────────────────

func test_allocating_a_compromiser_node_grants_the_owner_corruption_aspect() -> void:
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"corruption_aspect")
	_attach(loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"corruption_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	assert_eq(_attacker.stat_board.get_value(&"corruption_aspect"), before + 1.0,
			"allocating grants +1")
	_alloc.force_deallocate(loose)
	assert_eq(_attacker.stat_board.get_value(&"corruption_aspect"), before,
			"deallocating removes it")


func test_a_temp_compromiser_grants_no_corruption_aspect() -> void:
	_attacker.stat_board.corruption_aspect.base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var before: float = _attacker.stat_board.get_value(&"corruption_aspect")
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_tip, _COMPROMISER_SCENE))
	assert_eq(_attacker.stat_board.get_value(&"corruption_aspect"), before,
			"a temp's modifiers never reach the board")
