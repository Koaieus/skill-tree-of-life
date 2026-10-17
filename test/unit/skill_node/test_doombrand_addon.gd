extends GutTest

## `doombrand_addon.tscn` — Curse × Addon. On the map it grants its owner +1
## `curse_aspect`; on a blade every contact lands its curse rider (folded
## through the attacker's `curse_stacks_per_hit`), and a node a Doombrand
## contact kills spills its curse multiplied by the [DoomSpillEffect]'s
## scale. The spill is computed on the shadow and rides the record, so a
## live replay lands the same amounts.
##
## Fixture: test_compromiser_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc — plus a Ward beside the plate so its spill
## has a non-core survivor.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DOOMBRAND_SCENE := preload("res://skill_node/addons/defs/doombrand_addon.tscn")
const _CURSE := preload("res://effects/status/curse.tres")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15
const _PLATE_CURSE := 8.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _plate: SkillNode
var _ward: SkillNode


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
	enemy_camp.id = &"doombrand_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	var plate_at := Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0
	_plate = _spawn("Plate", plate_at)
	var camp := _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_ward = _spawn("Ward", plate_at + Vector2(0.0, _SPACING * 3.0))
	_graph.add_edge(camp, _plate)
	_graph.add_edge(camp, _ward)
	_graph.add_edge(_ward, _plate)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, camp)
	_defender.core_location = camp
	_alloc.force_allocate(_defender, _plate)
	_alloc.force_allocate(_defender, _ward)
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
	var addon := _DOOMBRAND_SCENE.instantiate() as SkillNodeAddon
	node.add_child(addon)
	return addon


## The authored effect of [param type] on the scene's on-hit list.
func _effect(type: Variant) -> OnHitEffect:
	var addon := _DOOMBRAND_SCENE.instantiate() as SkillNodeAddon
	var found: OnHitEffect = null
	for e in addon.on_hit_effects:
		if is_instance_of(e, type):
			found = e
	addon.queue_free()
	return found


## The curse stacks the outcome's first landed curse carried.
func _curse(outcome: AttackOutcome) -> float:
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _CURSE:
			return status.power
	assert_true(false, "the doombrand vertex lands curse on its contact")
	return -1.0


## Curses the plate and sharpens the tip to kill it in one contact.
func _arm() -> void:
	_sharpen(_tip, 1.0e5)
	_plate.get_combat().apply_status(_CURSE, _PLATE_CURSE)


## The tip kills the cursed plate in a shadow (the live world untouched);
## returns the outcome.
func _kill_plate(branded: bool) -> AttackOutcome:
	if branded:
		_attach(_tip)
	await _settle()
	var shadow := CombatWorld.shadow()
	var outcome := _plan().resolve_against(shadow)
	shadow.free_shadow()
	return outcome


## The spill the outcome recorded from the plate onto the ward.
func _spill_to_ward(outcome: AttackOutcome) -> float:
	var sum := 0.0
	for hit in outcome.hits:
		for e in hit.deallocations:
			for t in e.spill:
				var to_real: SkillNode = t.to.real() if t.to != null else null
				if to_real == _ward:
					sum += t.amount
	return sum


# ── blade face: the curse rider ─────────────────────────────────────────────

func test_a_doombrand_contact_lands_its_curse_rider() -> void:
	_attach(_tip)
	await _settle()
	var rider := _effect(ApplyStatusEffect) as ApplyStatusEffect
	assert_eq(rider.def, _CURSE, "the rider is curse")
	assert_gt(_curse(_plan().resolve_against(CombatWorld.live())), 0.0)


func test_the_attackers_curse_stacks_per_hit_folds_into_the_rider() -> void:
	_attach(_tip)
	await _settle()
	var plain := _curse(_plan().resolve_against(CombatWorld.live()))
	var more := StatModifier.new()
	more.stat_id = &"curse_stacks_per_hit"
	more.value = 2.0
	_attacker.stat_board.add_modifier(more)
	await _settle()
	assert_eq(_curse(_plan().resolve_against(CombatWorld.live())), plain + 2.0,
			"the attacker's +2 folds into the rider")


# ── the doom: a kill spills multiplied ──────────────────────────────────────

func test_a_doombrand_kill_spills_scaled_against_a_plain_kill() -> void:
	_arm()
	var plain := _spill_to_ward(await _kill_plate(false))
	assert_gt(plain, 0.0, "precondition: a plain kill spills onto the ward")
	var doomed_outcome := await _kill_plate(true)
	var doomed := _spill_to_ward(doomed_outcome)
	# The contact's own curse rider lands ahead of the killing hit, so the
	# plate dies holding its curse plus the rider's: the doom scales both.
	var held := (_PLATE_CURSE + _curse(doomed_outcome)) / _PLATE_CURSE
	var doom := _effect(DoomSpillEffect) as DoomSpillEffect
	assert_almost_eq(doomed / plain, held * doom.spill_scale, 0.0001,
			"the doom multiplies the plate's spill, rider curse included, by the effect's scale")


func test_a_live_replay_lands_the_doomed_spill() -> void:
	_arm()
	var outcome := await _kill_plate(true)
	var computed := _spill_to_ward(outcome)
	assert_gt(computed, _PLATE_CURSE / 2.0, "precondition: the doom scaled the spill")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	var battle := BattleSystem.new()
	battle.allocation_system = _alloc
	battle.graph = _graph
	add_child_autofree(battle)
	var before := _ward.get_combat().get_status_power(&"curse")
	OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	assert_false(_plate.is_allocated(), "precondition: the replay stripped the plate")
	assert_almost_eq(_ward.get_combat().get_status_power(&"curse") - before, computed, 0.0001,
			"the peer lands the same doomed spill")


# ── temp face + map face ────────────────────────────────────────────────────

func test_a_temp_doombrand_costs_2_blade_size_and_1_curse_aspect() -> void:
	var costs := SkillNodeAddon.temp_costs_of(_DOOMBRAND_SCENE)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"curse_aspect", 0), 1)


func test_allocating_a_doombrand_node_grants_the_owner_curse_aspect() -> void:
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"curse_aspect")
	_attach(loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"curse_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	assert_eq(_attacker.stat_board.get_value(&"curse_aspect"), before + 1.0,
			"allocating grants +1")
	_alloc.force_deallocate(loose)
	assert_eq(_attacker.stat_board.get_value(&"curse_aspect"), before,
			"deallocating removes it")


func test_a_temp_doombrand_grants_no_curse_aspect() -> void:
	_attacker.stat_board.facet(&"curse", StatDef.Role.ASPECT).base_value = 1.0
	_attacker.stat_board.blade_size.base_value = 20.0
	await _settle()
	var before: float = _attacker.stat_board.get_value(&"curse_aspect")
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _attacker
	plan.set_pivot(_pivot)
	plan.toggle_member(_mid)
	plan.toggle_member(_tip)
	assert_true(plan.apply_temp_upgrade(_tip, _DOOMBRAND_SCENE), "fits the budget")
	await _settle()
	assert_eq(_attacker.stat_board.get_value(&"curse_aspect"), before,
			"the temp face never reaches the entity board")
