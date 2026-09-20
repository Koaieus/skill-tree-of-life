extends GutTest

## [WitherStatus] (#966, hub #952): a MULTIPLY on node-local `healing_received`
## of `1 - factor_per_stack × stacks` — uncapped, so 10 stacks (at 0.1) block
## healing and 20 invert it. Below zero a heal is TRUE damage that leaves D-9's
## regen gate open (the "undead" case — [method NodeCombat.heal_damage]), so
## the ramp keeps climbing and the node heals itself to death. Stacks halve
## per tick (`DecayMode.FRACTION`) and the modifier follows them down. Same
## planted-modifier shape as ArmorBreak, including the shadow-isolation rule:
## replace, never mutate, the found modifier. Authored `wither.tres` values
## are the owner's knobs and are never pinned here.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _def: WitherStatus
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Withered"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node

	_def = WitherStatus.new()
	_def.id = &"wither"
	_def.factor_per_stack = 0.1
	_def.power_max = 0.0
	_def.decay_mode = StatusDef.DecayMode.FRACTION
	_def.decay_per_tick = 0.5
	_def.reapply = StatusDef.Reapply.ACCUMULATE


func after_each() -> void:
	for sh in _shadows:
		sh.free_shadow()


func _combat() -> NodeCombat:
	return _node.get_combat()


func _received() -> float:
	return float(_node.get_local_value(&"healing_received"))


func _multipliers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Stat = _node.node_board.get_stat(&"healing_received") if _node.node_board != null else null
	if s != null:
		out.assign(s.bins.multipliers)
	return out


func _set_hp(current: float, cap: float) -> void:
	_entity.stat_board.get_stat(&"node_health").base_value = cap
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(current)


func _hp() -> float:
	return (_node.node_board.get_stat(&"node_health") as PoolStat).current


# ── The multiplier ───────────────────────────────────────────────────────────

func test_five_stacks_read_half_healing_received() -> void:
	_combat().apply_status(_def, 5.0)
	assert_almost_eq(_received(), 0.5, 0.001, "1 - 0.1 × 5")
	assert_eq(_multipliers().size(), 1, "one planted modifier, not one per apply")


func test_ten_stacks_block_and_twenty_invert() -> void:
	_combat().apply_status(_def, 10.0)
	assert_almost_eq(_received(), 0.0, 0.001, "10 stacks: healing blocked")
	_combat().apply_status(_def, 10.0)
	assert_eq(_combat().get_status_power(&"wither"), 20.0, "uncapped, ACCUMULATE")
	assert_almost_eq(_received(), -1.0, 0.001, "20 stacks: fully inverted")
	assert_eq(_multipliers().size(), 1, "re-plant replaces, never stacks modifiers")


# ── Acceptance 4: decay follows stacks down, removal restores 1.0 ───────────

func test_stacks_halve_and_the_modifier_follows_until_removal_restores_one() -> void:
	_combat().apply_status(_def, 8.0)
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"wither"), 4.0)
	assert_almost_eq(_received(), 0.6, 0.001, "4 stacks after one halving")
	_combat().tick_statuses()  # 2
	_combat().tick_statuses()  # 1
	assert_almost_eq(_received(), 0.9, 0.001)
	_combat().tick_statuses()  # 0.5 → tail cleared → removed
	assert_eq(_combat().get_status_power(&"wither"), 0.0, "tail below 1 is removed")
	assert_almost_eq(_received(), 1.0, 0.001, "healing_received reads 1.0 again")
	assert_eq(_multipliers().size(), 0, "the modifier is stripped on removal")


# ── Acceptance 2: the ramp keeps climbing on a withered node ────────────────

func test_withered_node_regens_itself_to_death_with_a_climbing_ramp() -> void:
	_set_hp(100.0, 200.0)
	_entity.stat_board.get_stat(&"node_healing").base_value = 5.0
	_entity.stat_board.get_stat(&"node_healing_ramp").base_value = 2.0
	_combat().apply_status(_def, 20.0)  # ×(1 - 2) = -1
	_node._damaged_since_upkeep = false
	_node.regen_stacks = 0
	_node.apply_turn_regen()
	assert_almost_eq(_hp(), 95.0, 0.001, "upkeep 1: loses base (5)")
	_node.apply_turn_regen()
	assert_almost_eq(_hp(), 88.0, 0.001, "upkeep 2: loses base + ramp (7)")
	_node.apply_turn_regen()
	assert_almost_eq(_hp(), 79.0, 0.001, "upkeep 3: loses base + 2·ramp (9) — the ramp climbs")
	assert_eq(_node.regen_stacks, 3)
	# A real hit still resets the ramp, as today.
	_combat().take_damage(1.0, null)  # lands as min_damage_taken's floor, whatever it is
	var after_hit := _hp()
	assert_true(_node._damaged_since_upkeep, "a real hit closes the gate")
	_node.apply_turn_regen()
	assert_eq(_node.regen_stacks, 0, "the gated upkeep resets the ramp")
	assert_almost_eq(_hp(), after_hit, 0.001, "and heals (so damages) nothing")


# ── Acceptance 3: the core's own aura heal damages it, overflow hits the pool ─

func test_a_withered_core_takes_the_aura_heal_as_damage_and_overflows_to_the_entity_pool() -> void:
	_set_hp(3.0, 50.0)
	var pool := _entity.stat_board.get_stat(&"health") as PoolStat
	var pool_before := pool.current
	_combat().apply_status(_def, 20.0)
	# HealAuraEffect's only door is heal_damage — covered at the door, not
	# through a mounted aura.
	_combat().heal_damage(8.0, null)
	assert_almost_eq(_hp(), 0.0, 0.001, "the core node's 3 HP are gone")
	assert_almost_eq(pool.current, pool_before - 5.0, 0.001,
			"the 5 overflow reaches the entity pool via the existing core route")
	assert_false(_node._damaged_since_upkeep, "still ungated")


# ── Acceptance 5: shadow apply never writes live ────────────────────────────

func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_combat().apply_status(_def, 2.0)
	var live_mods := _multipliers()
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_node)
	shadow.apply_status(_def, 18.0)

	assert_almost_eq(float(shadow.get_local_value(&"healing_received")), -1.0, 0.001,
			"the shadow reads the inverted value")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
			"the live modifier instance is untouched by the shadow resolve")
	assert_almost_eq(_received(), 0.8, 0.001, "live world unchanged (still 2 stacks)")


# ── Authored content loads and is wired (values are the owner's knobs) ──────

func test_authored_wither_loads_and_names_its_pair() -> void:
	var w := load("res://effects/status/wither.tres") as WitherStatus
	assert_not_null(w, "wither.tres is a WitherStatus")
	if w == null:
		return
	assert_eq(w.id, &"wither")
	assert_eq(w.potency_stat_id, &"wither_potency")
	assert_eq(w.resistance_stat_id, &"wither_resistance")
	assert_true(w.tags.has(&"debuff"))
	assert_true(w.factor_per_stack > 0.0, "a per-stack factor is authored")
	assert_eq(w.decay_mode, StatusDef.DecayMode.FRACTION)
	assert_true(w.power_max <= 0.0, "uncapped")
