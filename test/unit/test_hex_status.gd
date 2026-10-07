extends GutTest

## Hexed: an authored `incoming_modifiers` entry on the status — an attacker's
## `crit_chance` read against the host gains an ADD_BONUS of `rate × power`,
## power summed over the node's rows and its owner's (a core's hex reads
## entity-wide). [method NodeCombat.incoming_overlays] is the door;
## [method CritRoll.chance_for] folds it after the attacker's whole fold, so a
## hexed target opens the draw for a zero-investment attacker and an unhexed
## one leaves the stream untouched. The rate is read off the def, never pinned.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _HEXED := preload("res://effects/status/hexed.tres")

var _attacker: Entity
var _defender: Entity
## a0, a1: attacker's. t (hexed in most cases), u (defender core): defender's.
## x: unowned.
var _n: Dictionary = {}


func before_each() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	for i in 5:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = ["a0", "a1", "t", "u", "x"][i]
		graph.add_skill_node(node)
		node.global_position = Vector2(i * 300.0, 0.0)
		_n[node.name] = node
	graph.add_edge(_n.a0, _n.a1)
	graph.add_edge(_n.a1, _n.t)
	graph.add_edge(_n.t, _n.u)
	graph.add_edge(_n.u, _n.x)

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.entities_container.add_child(_attacker)
	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _n.a0)
	alloc.force_allocate(_attacker, _n.a1)
	_attacker.core_location = _n.a0
	alloc.force_allocate(_defender, _n.t)
	alloc.force_allocate(_defender, _n.u)
	_defender.core_location = _n.u


func _rate() -> float:
	return _HEXED.incoming_modifiers[0].value


func _hit(target: SkillNode, read_node: SkillNode = null, heal := false) -> HitInstance:
	var hit: HitInstance = HealInstance.new() if heal else DamageInstance.new()
	hit.attacker = _attacker
	hit.read_node = read_node if read_node != null else _n.a1
	hit.target = target
	hit.amount = 5.0
	return hit


func _bonus(overlays: Array[ModifierBins]) -> float:
	var total := 0.0
	for b in overlays:
		total += b.bonus_add
	return total


# ── 1. The door ─────────────────────────────────────────────────────────────

func test_authored_entry_is_a_crit_chance_add_bonus() -> void:
	assert_eq(_HEXED.incoming_modifiers.size(), 1)
	var m: StatModifier = _HEXED.incoming_modifiers[0]
	assert_eq(m.stat_id, &"crit_chance")
	assert_eq(m.operation, StatModifier.Operation.ADD_BONUS)
	assert_gt(m.value, 0.0)


func test_node_and_owner_stacks_sum_into_one_bonus() -> void:
	_n.t.get_combat().apply_status(_HEXED, 3.0)
	_defender.get_combat().apply_status(_HEXED, 4.0)
	var overlays: Array[ModifierBins] = _n.t.get_combat().incoming_overlays(&"crit_chance")
	assert_false(overlays.is_empty(), "a hexed node answers an overlay")
	assert_almost_eq(_bonus(overlays), _rate() * 7.0, 0.0001, "rate × (N + M)")
	var core: Array[ModifierBins] = _n.u.get_combat().incoming_overlays(&"crit_chance")
	assert_almost_eq(_bonus(core), _rate() * 4.0, 0.0001,
		"the owner's hex reads on every owned node")


func test_unowned_node_reads_its_own_stacks_only() -> void:
	# Hexed is CLEAR (never lands unowned); a LINGER copy is the row a node
	# keeps past losing its owner.
	var lingering := _HEXED.duplicate() as StatusDef
	lingering.on_dealloc = StatusDef.OnDealloc.LINGER
	_defender.get_combat().apply_status(_HEXED, 4.0)
	_n.x.get_combat().apply_status(lingering, 2.0)
	assert_eq(_n.x.get_combat().get_status_power(&"hex"), 2.0, "fixture: the row landed")
	var overlays: Array[ModifierBins] = _n.x.get_combat().incoming_overlays(&"crit_chance")
	assert_almost_eq(_bonus(overlays), _rate() * 2.0, 0.0001)


func test_unhexed_node_and_other_stat_answer_nothing() -> void:
	assert_eq(_n.t.get_combat().incoming_overlays(&"crit_chance").size(), 0, "unhexed → []")
	_n.t.get_combat().apply_status(_HEXED, 3.0)
	assert_eq(_n.t.get_combat().incoming_overlays(&"crit_multiplier").size(), 0,
		"a stat no entry names → []")


# ── 2. Stream stability ─────────────────────────────────────────────────────

func test_hexed_target_opens_the_draw_for_a_zero_crit_attacker() -> void:
	var stacks := ceilf(1.5 / _rate())
	_n.t.get_combat().apply_status(_HEXED, stacks)
	assert_almost_eq(CritRoll.chance_for(_hit(_n.u)), 0.0, 0.0001, "fixture: no attacker crit")
	var rng := CritRoll.stream_for(4242)
	for i in 5:
		var hit := _hit(_n.t)
		CritRoll.decide(hit, rng)
		assert_true(hit.is_crit, "every damage hit on a deep hex crits")
	var before := rng.state
	for i in 5:
		var plain := _hit(_n.u)
		CritRoll.decide(plain, rng)
		assert_false(plain.is_crit)
	assert_eq(rng.state, before, "an unhexed target never draws")


func test_every_attacker_branch_folds_the_overlay() -> void:
	_n.t.get_combat().apply_status(_HEXED, 4.0)
	var want := _rate() * 4.0
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t)), want, 0.0001, "read-node branch")
	var entity_read := _hit(_n.t)
	entity_read.read_node = null
	assert_almost_eq(CritRoll.chance_for(entity_read), want, 0.0001, "entity fallback")
	var no_attacker := _hit(_n.t)
	no_attacker.attacker = null
	no_attacker.read_node = null
	assert_almost_eq(CritRoll.chance_for(no_attacker), want, 0.0001, "no attacker")


# ── 3. ADD_BONUS placement ──────────────────────────────────────────────────

func test_bonus_lands_after_the_attackers_increases() -> void:
	var cc: Stat = _attacker.stat_board.get_stat(&"crit_chance")
	cc.base_value = 0.1
	var c := CritRoll.chance_for(_hit(_n.u))
	assert_gt(c, 0.0, "fixture: some base crit")
	var inc := StatModifier.new()
	inc.stat_id = &"crit_chance"
	inc.operation = StatModifier.Operation.INCREASE
	inc.value = 100.0
	cc.add_modifier(inc, _attacker.stat_board)
	assert_almost_eq(CritRoll.chance_for(_hit(_n.u)), 2.0 * c, 0.0001, "fixture: +100% doubles")
	_n.t.get_combat().apply_status(_HEXED, 3.0)
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t)), 2.0 * c + _rate() * 3.0, 0.0001,
		"2c + rate × N, not 2(c + rate × N)")


# ── 4. Heals ────────────────────────────────────────────────────────────────

func test_heal_on_hexed_node_is_unaffected() -> void:
	_n.t.get_combat().apply_status(_HEXED, 30.0)
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t, null, true)),
		CritRoll.chance_for(_hit(_n.u, null, true)), 0.0001)
	var rng := CritRoll.stream_for(7)
	var before := rng.state
	CritRoll.decide(_hit(_n.t, null, true), rng)
	assert_eq(rng.state, before, "a heal on a hexed node never draws")


# ── 5. Load check ───────────────────────────────────────────────────────────

func test_multiply_entry_is_refused() -> void:
	var mult := StatModifier.new()
	mult.stat_id = &"crit_chance"
	mult.operation = StatModifier.Operation.MULTIPLY
	mult.value = 3.0
	var bonus := StatModifier.new()
	bonus.stat_id = &"crit_chance"
	bonus.operation = StatModifier.Operation.ADD_BONUS
	bonus.value = 0.1
	var def := StatusDef.new()
	def.id = &"throwaway"
	def.power_max = 0.0
	def.reapply = StatusDef.Reapply.ACCUMULATE
	def.incoming_modifiers = [mult, bonus]
	assert_push_error("MULTIPLY")
	_n.t.get_combat().apply_status(def, 2.0)
	var overlays: Array[ModifierBins] = _n.t.get_combat().incoming_overlays(&"crit_chance")
	assert_eq(overlays.size(), 1)
	if overlays.size() == 1:
		assert_eq(overlays[0].multipliers.size(), 0, "the MULTIPLY entry is ignored")
		assert_almost_eq(overlays[0].bonus_add, 0.2, 0.0001, "the sum entry still lands")


# ── 6. Shadow ───────────────────────────────────────────────────────────────

func test_a_shadow_world_reads_its_own_hex() -> void:
	_n.t.get_combat().apply_status(_HEXED, 3.0)
	_defender.get_combat().apply_status(_HEXED, 2.0)
	var world := CombatWorld.shadow()
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t), world), _rate() * 5.0, 0.0001,
		"the snapshot carries node and owner rows")
	world.combat_for(_n.t).apply_status(_HEXED, 2.0)
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t), world), _rate() * 7.0, 0.0001,
		"a shadow landing moves the shadow read")
	assert_almost_eq(CritRoll.chance_for(_hit(_n.t)), _rate() * 5.0, 0.0001,
		"and never the live one")


# ── 7. The jinx goes off: a crit taken spends the hex ───────────────────────

func _crit(target: SkillNode, crit := true) -> DamageInstance:
	var hit := _hit(target) as DamageInstance
	hit.is_crit = crit
	return hit


func _land(hit: HitInstance, world: CombatWorld = null) -> void:
	OutcomeApplier.land_one(hit, world if world != null else CombatWorld.live())


func _hex(node: SkillNode) -> float:
	return node.get_combat().get_status_power(&"hex")


func test_a_crit_taken_spends_the_hex_and_a_plain_hit_does_not() -> void:
	_n.t.get_combat().apply_status(_HEXED, 4.0)
	_land(_crit(_n.t, false))
	assert_eq(_hex(_n.t), 4.0, "a non-crit hit leaves the hex")
	_land(_crit(_n.t))
	assert_eq(_hex(_n.t), floorf(4.0 * _HEXED.spend_factor), "a crit keeps floor(P × factor)")


func test_a_crit_on_any_node_spends_the_entitys_hex_not_a_siblings() -> void:
	_defender.get_combat().apply_status(_HEXED, 5.0)
	_n.u.get_combat().apply_status(_HEXED, 4.0)
	_land(_crit(_n.t))
	assert_eq(_defender.get_combat().get_status_power(&"hex"),
		floorf(5.0 * _HEXED.spend_factor), "the core's entity-wide hex spends")
	assert_eq(_hex(_n.u), 4.0, "node B's own rows are untouched")


func test_spend_factor_one_is_the_identity() -> void:
	var def := _HEXED.duplicate() as HexStatus
	def.spend_factor = 1.0
	_n.t.get_combat().apply_status(def, 4.0)
	_land(_crit(_n.t))
	assert_eq(_hex(_n.t), 4.0)


func test_a_crit_heal_spends_nothing() -> void:
	_n.t.get_combat().apply_status(_HEXED, 4.0)
	var heal := _hit(_n.t, null, true)
	heal.is_crit = true
	_land(heal)
	assert_eq(_hex(_n.t), 4.0)


func test_a_shadow_landing_and_a_live_landing_spend_alike() -> void:
	_n.t.get_combat().apply_status(_HEXED, 4.0)
	_defender.get_combat().apply_status(_HEXED, 3.0)
	var world := CombatWorld.shadow()
	_land(_crit(_n.t), world)
	var shadow_node: float = world.combat_for(_n.t).get_status_power(&"hex")
	var shadow_entity: float = world.combat_for_entity(_defender).get_status_power(&"hex")
	assert_eq(shadow_node, floorf(4.0 * _HEXED.spend_factor), "the shadow spends")
	assert_eq(_hex(_n.t), 4.0, "and the live world is untouched by it")
	_land(_crit(_n.t))
	assert_eq(_hex(_n.t), shadow_node, "the live landing reproduces the node's spend")
	assert_eq(_defender.get_combat().get_status_power(&"hex"), shadow_entity,
		"and the entity's")
