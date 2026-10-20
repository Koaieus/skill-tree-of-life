extends GutTest

## `shredder_addon.tscn` — Sunder x Addon. On the map it grants its owner +1
## `sunder_aspect`; on a blade every contact lands Sunder folded through the
## carrier's local `sunder_stacks_per_hit` (+2 per allocation level), and at
## 3/X a [DefenderStatShare] adds a share of the struck node's live armor on
## top. The rider lands before its paired hit, so the contact's own damage
## goes through the armor it just broke.
##
## Fixture: test_ashfall_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc, its armor arranged with a node-local
## ADD_BASE.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SHREDDER_PATH := "res://skill_node/addons/defs/shredder_addon.tscn"
const _SUNDER := preload("res://effects/status/sunder.tres")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15
const _PLATE_ARMOR := 20.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _plate: SkillNode
var _camp: SkillNode


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


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"shredder_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_plate = _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	_camp = _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_graph.add_edge(_camp, _plate)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _camp)
	_defender.core_location = _camp
	_alloc.force_allocate(_defender, _plate)
	_mid.add_child(_CLAMP_SCENE.instantiate())


func _scene() -> PackedScene:
	return load(_SHREDDER_PATH) as PackedScene


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


func _plate_armor() -> float:
	return float(CombatWorld.live().combat_for(_plate).get_local_value(&"armor"))


## Moves the plate's live armor to exactly [param value], whatever it starts at.
func _set_plate_armor(value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - _plate_armor()
	_plate.add_local_modifier(m)
	assert_almost_eq(_plate_armor(), value, 0.001, "arranged plate armor")


## The tip filled to [param level]/X (carrying Shredder when [param shredder]),
## then one real swing resolved on a shadow (the live world untouched).
func _swing_at(level: int, shredder: bool = true) -> AttackOutcome:
	if shredder:
		var scene := _scene()
		assert_not_null(scene, "the Shredder scene exists")
		if scene == null:
			return AttackOutcome.new()
		_tip.add_child(scene.instantiate())
	_tip.stake_level = maxi(_tip.stake_level, level)
	_alloc.force_fill(_tip, level)
	await _settle()
	var shadow := CombatWorld.shadow()
	var outcome := _plan().resolve_against(shadow)
	shadow.free_shadow()
	return outcome


## Sunder stacks the outcome landed on the plate, summed; -1 when none.
func _sunder_on_plate(outcome: AttackOutcome) -> float:
	var sum := -1.0
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _SUNDER and status.target == _plate:
			sum = maxf(sum, 0.0) + status.power
	return sum


## Damage the outcome dealt the plate, summed.
func _damage_on_plate(outcome: AttackOutcome) -> float:
	var sum := 0.0
	for hit in outcome.hits:
		var dmg := hit as DamageInstance
		if dmg != null and dmg.target == _plate:
			sum += dmg.amount
	return sum


## The authored node-local `sunder_stacks_per_hit` grant per allocation level.
func _flat_per_level() -> float:
	var scene := _scene()
	if scene == null:
		return -1.0
	var addon := scene.instantiate() as SkillNodeAddon
	var flat := -1.0
	for m in addon.local_modifiers:
		if m.stat_id == &"sunder_stacks_per_hit" and not (m is LevelGatedModifier):
			flat = m.value
	addon.queue_free()
	return flat


## The rider's authored armor share.
func _share() -> DefenderStatShare:
	var scene := _scene()
	if scene == null:
		return null
	var addon := scene.instantiate() as SkillNodeAddon
	var found: DefenderStatShare = null
	for e in addon.on_hit_effects:
		var rider := e as ApplyStatusEffect
		if rider == null or rider.def != _SUNDER:
			continue
		for t in rider.stack_terms:
			if t is DefenderStatShare:
				found = t
	addon.queue_free()
	return found


# ── the stat ────────────────────────────────────────────────────────────────

func test_sunder_names_its_stacks_stat_and_an_entity_grant_folds_in() -> void:
	assert_eq(_SUNDER.stacks_stat_id(), &"sunder_stacks_per_hit",
			"the stat exists, so Sunder's STACKS_PER_HIT facet resolves")
	var board := _attacker.stat_board
	var plain := _SUNDER.stacks_per_hit(board, 1.0)
	var more := StatModifier.new()
	more.stat_id = &"sunder_stacks_per_hit"
	more.value = 2.0
	board.add_modifier(more)
	assert_eq(_SUNDER.stacks_per_hit(board, 1.0), plain + 2.0,
			"a Sunder arrow's authored power folds the attacker's +2")


# ── blade face: flat below 3/X, flat + armor share from 3/X ─────────────────

func test_a_2_of_x_contact_lands_the_flat_stacks_only() -> void:
	_set_plate_armor(_PLATE_ARMOR)
	var outcome := await _swing_at(2)
	assert_gt(_flat_per_level(), 0.0, "precondition: a local sunder_stacks_per_hit grant")
	assert_eq(_sunder_on_plate(outcome), _flat_per_level() * 2.0,
			"2/X: the flat part alone, the armor share is gated")


func test_a_3_of_x_contact_adds_the_armor_share() -> void:
	_set_plate_armor(_PLATE_ARMOR)
	var outcome := await _swing_at(3)
	var share := _share()
	assert_not_null(share, "the rider carries a DefenderStatShare")
	if share == null:
		return
	assert_eq(share.stat_id, &"armor")
	assert_eq(share.unlock_level, 3, "the share is the 3/X unlock")
	assert_eq(_sunder_on_plate(outcome),
			StatusDef.round_half_up(_flat_per_level() * 3.0 + share.ratio * _PLATE_ARMOR),
			"3/X: flat + ratio x the plate's armor")


func test_a_target_without_armor_takes_the_flat_part_only() -> void:
	_set_plate_armor(-3.0)
	var outcome := await _swing_at(3)
	assert_eq(_sunder_on_plate(outcome), _flat_per_level() * 3.0,
			"armor at or below 0 adds no share")


func test_the_contact_damage_goes_through_the_armor_it_just_broke() -> void:
	_set_plate_armor(_PLATE_ARMOR)
	var plain := _damage_on_plate(await _swing_at(3, false))
	assert_gt(plain, 0.0, "precondition: the plain contact deals damage")
	var shredded := _damage_on_plate(await _swing_at(3))
	assert_gt(shredded, plain, "the rider lands first, so the hit sees the reduced armor")


# ── map face and temp price ─────────────────────────────────────────────────

func test_a_temp_shredder_costs_2_blade_size_and_1_sunder_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	assert_true(SkillNodeAddon.temp_placeable_of(scene))
	var costs := SkillNodeAddon.temp_costs_of(scene)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"sunder_aspect", 0), 1)


func test_allocating_a_shredder_node_grants_the_owner_sunder_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"sunder_aspect")
	loose.add_child(scene.instantiate())
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"sunder_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"sunder_aspect"), before + 1.0)
