extends GutTest

## WatchtowerAddon grants a node-local +250 vision_range on its carrier only —
## same localization contract as SpikeRing on blade_damage
## (test_blade_damage_localization.gd), but for VisionSystem's per-node read
## (systems/vision_system.gd get_local_value(&"vision_range")).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _WATCHTOWER_SCENE := preload("res://skill_node/addons/defs/watchtower_addon.tscn")
const _SCOUTED := preload("res://effects/status/scouted.tres")
## A rigid spine (mid welded) traces the nominal radius the plate sits on.
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _setup() -> Dictionary:
	var graph := TestWorld.create(self).graph
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var source := _spawn_node(graph, "Source")
	var tower := _spawn_node(graph, "Tower")
	await get_tree().process_frame

	var alloc := TestWorld.around(graph).allocator()
	alloc.force_allocate(entity, source)
	alloc.force_allocate(entity, tower)

	tower.add_child(_WATCHTOWER_SCENE.instantiate())

	return {"graph": graph, "entity": entity, "source": source, "tower": tower}


func test_watchtower_grants_node_local_vision_bonus() -> void:
	var ctx: Dictionary = await _setup()
	var source: SkillNode = ctx.source
	var tower: SkillNode = ctx.tower
	var base_vision: float = float(source.get_local_value(&"vision_range"))
	var tower_vision: float = float(tower.get_local_value(&"vision_range"))
	assert_gt(tower_vision, base_vision,
			"watchtower node must see farther than the bare wielder value")


func test_watchtower_removed_reverts_vision() -> void:
	var ctx: Dictionary = await _setup()
	var source: SkillNode = ctx.source
	var tower: SkillNode = ctx.tower
	var addon := tower.get_addons()[0]
	addon.free()
	await get_tree().process_frame
	assert_almost_eq(float(tower.get_local_value(&"vision_range")),
			float(source.get_local_value(&"vision_range")), 0.001,
			"removing the watchtower must revert to the bare wielder value")


# ── blade + map faces (test_compromiser_addon.gd's spine) ───────────────────
#
# Pivot, mid, tip in a line; a hostile plate on the tip's arc. On the map the
# watchtower grants its owner +1 `scout_aspect`; on a blade its vertex lands
# `scouted` for the attacker's camp on every contact, with toxin's ladder:
# +1 `scout_stacks_per_hit` local (scales with allocation) and ×2 at 3/X.

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode


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


func _spine() -> void:
	_graph = TestWorld.create(self).graph
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"watchtower_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	var plate := _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	await get_tree().process_frame

	_alloc = TestWorld.around(_graph).allocator()
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	# The plate is territory, not the core: a cracked core would fall the
	# status through to the entity host and hide the node landing.
	var camp := _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_graph.add_edge(camp, plate)
	_alloc.force_allocate(_defender, camp)
	_defender.core_location = camp
	_alloc.force_allocate(_defender, plate)
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 20.0
	_tip.add_local_modifier(sharp)
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
	var addon := _WATCHTOWER_SCENE.instantiate() as SkillNodeAddon
	node.add_child(addon)
	return addon


## Stakes [param node] to [param level] and fills it there through the
## AllocationSystem — the real allocation path, never a written level.
func _fill(node: SkillNode, level: int) -> void:
	node.stake_level = level
	_alloc.force_fill(node, level)


## The scouted stacks the outcome's first landed scout row carried.
func _scouted(outcome: AttackOutcome) -> float:
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _SCOUTED:
			return status.power
	assert_true(false, "the watchtower vertex lands scouted on its contact")
	return -1.0


func _stacks_at(level: int) -> float:
	await _spine()
	if level > 1:
		_fill(_tip, level)
	_attach(_tip)
	await _settle()
	return _scouted(_plan().resolve_against(CombatWorld.live()))


func test_a_watchtower_on_a_blade_node_lands_scouted_for_the_attackers_camp() -> void:
	await _spine()
	_attach(_tip)
	await _settle()
	var outcome := _plan().resolve_against(CombatWorld.live())
	assert_gt(_scouted(outcome), 0.0, "a contact lands scouted stacks")
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _SCOUTED:
			assert_eq(status.attacker, _attacker, "keyed to the attacker's camp")


## Toxin's ladder shape (test_addon_on_hit.gd): the 2/X fold is twice the 1/X
## one (the local +stacks scales with allocation), and 3/X doubles 3 × the
## 1/X fold.
func test_the_stacks_ladder_follows_allocation_and_doubles_at_3_of_x() -> void:
	var one: float = await _stacks_at(1)
	var two: float = await _stacks_at(2)
	var three: float = await _stacks_at(3)
	assert_gt(one, 0.0, "1/X lands scouted")
	assert_eq(two, one * 2.0, "the local stacks scale with allocation")
	assert_eq(three, one * 3.0 * 2.0, "the 3/X unlock doubles the node's fold")


func test_the_attackers_scout_stacks_per_hit_folds_into_the_rider() -> void:
	await _spine()
	var more := StatModifier.new()
	more.stat_id = &"scout_stacks_per_hit"
	more.value = 2.0
	_attacker.stat_board.add_modifier(more)
	var base: float = await _stacks_at_tip_bare()
	assert_eq(base, 3.0, "1 local + 2 from the attacker's board")


func _stacks_at_tip_bare() -> float:
	_attach(_tip)
	await _settle()
	return _scouted(_plan().resolve_against(CombatWorld.live()))


func test_a_temp_watchtower_lands_scouted_like_a_map_one() -> void:
	await _spine()
	_attacker.stat_board.facet(&"scout", StatDef.Role.ASPECT).base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_tip, _WATCHTOWER_SCENE), "fits the budget")
	await _settle()
	assert_gt(_scouted(plan.resolve_against(CombatWorld.live())), 0.0)


func test_a_temp_watchtower_costs_1_blade_size_and_1_scout_aspect() -> void:
	var costs := SkillNodeAddon.temp_costs_of(_WATCHTOWER_SCENE)
	assert_eq(costs.get(&"blade_size", 0), 1)
	assert_eq(costs.get(&"scout_aspect", 0), 1)


func test_allocating_a_watchtower_node_grants_the_owner_scout_aspect() -> void:
	await _spine()
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"scout_aspect")
	_attach(loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"scout_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	assert_eq(_attacker.stat_board.get_value(&"scout_aspect"), before + 1.0,
			"allocating grants +1")
	_alloc.force_deallocate(loose)
	assert_eq(_attacker.stat_board.get_value(&"scout_aspect"), before,
			"deallocating removes it")


func test_a_temp_watchtower_grants_no_scout_aspect() -> void:
	await _spine()
	_attacker.stat_board.facet(&"scout", StatDef.Role.ASPECT).base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var before: float = _attacker.stat_board.get_value(&"scout_aspect")
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_tip, _WATCHTOWER_SCENE))
	assert_eq(_attacker.stat_board.get_value(&"scout_aspect"), before,
			"a temp's modifiers never reach the board")
