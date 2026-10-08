extends GutTest

## A swing's temp addon reaches the status landing: its node-local
## `<status>_stacks_per_hit` folds into the stacks its own vertex lands, the
## same number the addon gives when placed for good — and no other read sees it.
##
## Fixture: test_addon_on_hit.gd's spine — pivot, mid, tip in a line, a hostile
## plate on the tip's arc.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://effects/status/poison.tres")
const _BARE_SCENE := preload("res://test/fixtures/addons/bare_addon.tscn")
## A rigid spine (mid welded) traces the nominal radius the plate sits on; a
## floppy one curls inward and misses — test_bunker_break_live.gd's finding.
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15
const _TIP_IDX := 2

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


func _set_spikes_cap(node: SkillNode, cap: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spikes"
	mod.operation = StatModifier.Operation.SET
	mod.value = cap
	node.add_local_modifier(mod)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"temp_overlay_enemy"
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
	# status through to the entity host (#996) and hide the node landing.
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


## A bare addon carrying a node-local `+2 poison_stacks_per_hit` and a
## `poison` rider at power 1 — flags set before it enters the tree, so a temp
## never routes its modifiers onto the carrier's board.
func _stacking_addon(temporary: bool) -> SkillNodeAddon:
	var addon := _BARE_SCENE.instantiate() as SkillNodeAddon
	var stacks := StatModifier.new()
	stacks.stat_id = &"poison_stacks_per_hit"
	stacks.operation = StatModifier.Operation.ADD_BASE
	stacks.value = 2.0
	var locals: Array[StatModifier] = [stacks]
	addon.local_modifiers = locals
	var rider := ApplyStatusEffect.new()
	rider.def = _POISON
	rider.power = 1.0
	var effects: Array[OnHitEffect] = [rider]
	addon.on_hit_effects = effects
	addon.is_temporary = temporary
	return addon


func _status_hits(outcome: AttackOutcome) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for hit in outcome.hits:
		if hit is StatusInstance:
			out.append(hit)
	return out


func _landed_power(temporary: bool) -> float:
	_tip.add_child(_stacking_addon(temporary))
	await _settle()
	_plate.get_combat().refill(true)
	var landed := _status_hits(_plan().resolve_against(CombatWorld.live()))
	assert_eq(landed.size(), 1, "fixture: the tip's contact carries one rider")
	return landed[0].power if not landed.is_empty() else -1.0


func test_a_temp_addons_local_stacks_land_on_its_vertex_contact() -> void:
	assert_almost_eq(await _landed_power(true), 3.0, 0.0001,
			"authored 1 + the temp's local +2 on its own vertex")


func test_the_same_addon_placed_for_good_lands_the_same_stacks() -> void:
	assert_almost_eq(await _landed_power(false), 3.0, 0.0001,
			"a map addon and a one-swing temp share one formula")


## Outside a swing a landing carries no overlay lookup — the shape an arrow's
## or a spell's landing takes — so the temp's modifier reaches no such read.
func test_a_landing_read_from_the_carrier_outside_the_swing_lands_authored_stacks() -> void:
	_tip.add_child(_stacking_addon(true))
	await _settle()
	assert_almost_eq(float(_tip.get_combat().get_local_value(&"poison_stacks_per_hit")), 0.0, 0.0001,
			"the temp's local modifier is on no board")
	var landing := HitLanding.new()
	landing.attacker = _attacker
	landing.read_node = _tip
	landing.target = _plate
	_tip.get_addons()[0].on_hit_effects[0].apply(landing)
	assert_eq(landing.hits.size(), 1)
	if landing.hits.is_empty():
		return
	var status := landing.hits[0] as StatusInstance
	status.land_on(CombatWorld.live().combat_for(_plate), CombatWorld.live())
	assert_almost_eq(status.power, 1.0, 0.0001, "authored stacks only")
