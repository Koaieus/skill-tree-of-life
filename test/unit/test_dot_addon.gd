extends GutTest

## #951 — DotAddon's melee face: the blade vertex built from a carrier of
## `toxin_addon.tscn` applies `poison` on every contact it LANDS — that vertex
## only, and only when the vertex's own damage hit was admitted by the live
## gate (a popped vertex never re-pops through its status). The ranged face
## is the first shipped user of `SkillNodeAddon.entity_modifiers`.
##
## Fixture: test_bunker_break_live.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc. Spacing and turn fraction are that test's.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _TOXIN_SCENE := preload("res://skill_node/addons/toxin_addon.tscn")
const _POISON := preload("res://effects/status/poison.tres")
## A rigid spine (mid welded) traces the nominal radius the plate sits on; a
## floppy one curls inward and misses — test_bunker_break_live.gd's finding.
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")

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
	enemy_camp.id = &"dot_addon_enemy"
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


func _attach_toxin(node: SkillNode) -> DotAddon:
	var toxin := _TOXIN_SCENE.instantiate() as DotAddon
	node.add_child(toxin)
	return toxin


func _status_hits(outcome: AttackOutcome) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for hit in outcome.hits:
		if hit is StatusInstance:
			out.append(hit)
	return out


# ── melee face ───────────────────────────────────────────────────────────────

func test_the_toxic_vertex_lands_damage_and_poison_on_the_same_contact() -> void:
	_attach_toxin(_tip)
	await _settle()
	var outcome := _plan().resolve_against(CombatWorld.live())

	var damage := outcome.damage_hits()
	assert_gt(damage.size(), 0, "fixture: the tip must contact the plate")
	var statuses := _status_hits(outcome)
	assert_eq(statuses.size(), damage.size(),
			"one status per landed contact of the toxic vertex")
	if statuses.is_empty():
		return
	var status := statuses[0]
	assert_eq(status.def, _POISON, "the authored status")
	assert_eq(status.target, _plate)
	assert_eq(status.structural_key, damage[0].structural_key,
			"same beat as its damage hit")
	assert_true(status.power_resolved, "landed on the authority's own resolve")
	assert_gt(status.power, 0.0, "poison stacks landed")
	assert_gt(CombatWorld.live().combat_for(_plate).get_status_power(&"poison"), 0.0,
			"the plate carries poison after the swing")


func test_a_toxin_elsewhere_on_the_blade_leaves_the_contacting_vertex_clean() -> void:
	_attach_toxin(_mid)  # mid never reaches the plate; only the tip does
	await _settle()
	var outcome := _plan().resolve_against(CombatWorld.live())

	assert_gt(outcome.damage_hits().size(), 0, "fixture: the tip still contacts")
	assert_eq(_status_hits(outcome).size(), 0,
			"per-vertex: the un-toxic vertex applies nothing")


func test_a_refused_contact_applies_no_status_and_pops_once() -> void:
	_attach_toxin(_tip)
	_set_spikes_cap(_plate, 1.0)
	await _settle()
	var outcome := _plan().resolve_against(CombatWorld.live())

	assert_eq(outcome.popped_nodes, 1, "the spiked plate pops the tip exactly once")
	for status in _status_hits(outcome):
		assert_true(status.gated, "a status behind a refused contact is a dud")
		assert_eq(status.power, 0.0, "and lands nothing")
	assert_eq(CombatWorld.live().combat_for(_plate).get_status_power(&"poison"), 0.0,
			"no poison from a contact the gate refused")


# ── ranged face ──────────────────────────────────────────────────────────────

func test_allocating_a_toxin_node_grants_the_owner_poison_arrows() -> void:
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"poison_arrows_per_reload")
	var toxin := _attach_toxin(loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"poison_arrows_per_reload"), before,
			"unallocated: the modifier waits on the node")

	_alloc.force_allocate(_attacker, loose)
	var granted: float = toxin.entity_modifiers[0].value
	assert_eq(_attacker.stat_board.get_value(&"poison_arrows_per_reload"), before + granted,
			"allocating applies the authored entity modifier")

	_alloc.force_deallocate(loose)
	assert_eq(_attacker.stat_board.get_value(&"poison_arrows_per_reload"), before,
			"deallocating removes it")
