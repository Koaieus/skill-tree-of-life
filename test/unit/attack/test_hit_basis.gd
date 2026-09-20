extends GutTest

## [member HitInstance.basis]: a hit's `amount` is either a flat HP number
## ([constant HitInstance.AmountBasis.FLAT]) or a fraction of the TARGET's max hp
## ([constant HitInstance.AmountBasis.PERCENT_MAX]) that `land_on` resolves into HP
## once, against the landing slice — the same "amount is a coefficient until
## land" idiom [BladeDamageInstance] uses for its speed curve (#779). Damage
## and heal share one knob; a rebuilt [AttackRecord] carries the already-
## resolved number and never re-scales it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Scaled"
	# Flat board: formula test arranges its own stat inputs, tuned CON must not ride in.
	_entity.stat_board = TestBoards.flat_entity_board()
	# Hits crit (CritRoll.apply in land_on) — zero it so exact asserts hold.
	_entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


func _set_max_hp(hp: float) -> void:
	# node_health's cap derives from the OWNER's board (see test_poison_status).
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


func test_percent_max_damage_lands_a_fraction_of_the_targets_max_hp() -> void:
	_set_max_hp(40.0)
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE  # unmitigated, so the assert is exact
	hit.basis = HitInstance.AmountBasis.PERCENT_MAX
	hit.amount = 0.25
	hit.target = _node
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_current_hp(), 30.0, 0.001, "0.25 x 40 max hp = 10 damage")
	assert_almost_eq(hit.amount, 10.0, 0.001, "amount is resolved to HP at land")
	assert_almost_eq(hit.effective_amount, 10.0, 0.001)


func test_flat_damage_is_unchanged_by_the_default_basis() -> void:
	_set_max_hp(40.0)
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.amount = 7.0
	hit.target = _node
	assert_eq(hit.basis, HitInstance.AmountBasis.FLAT, "FLAT is the default")
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_current_hp(), 33.0, 0.001)


func test_percent_max_heal_restores_a_fraction_of_max_hp_clamped_at_cap() -> void:
	_set_max_hp(40.0)
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(10.0)
	var heal := HealInstance.new()
	heal.basis = HitInstance.AmountBasis.PERCENT_MAX
	heal.amount = 0.5
	heal.target = _node
	OutcomeApplier.land_one(heal, CombatWorld.live())
	assert_almost_eq(_node.get_current_hp(), 30.0, 0.001, "0.5 x 40 = 20 healed")
	assert_almost_eq(heal.effective_amount, 20.0, 0.001)

	var over := HealInstance.new()
	over.basis = HitInstance.AmountBasis.PERCENT_MAX
	over.amount = 1.0
	over.target = _node
	OutcomeApplier.land_one(over, CombatWorld.live())
	assert_almost_eq(_node.get_current_hp(), 40.0, 0.001, "clamped at the cap")
	assert_almost_eq(over.effective_amount, 10.0, 0.001, "effective is the post-clamp delta")


func test_percent_current_damage_chunks_the_targets_current_hp_and_is_never_lethal() -> void:
	_set_max_hp(40.0)
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(16.0)
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.basis = HitInstance.AmountBasis.PERCENT_CURRENT
	hit.amount = 0.5
	hit.target = _node
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_current_hp(), 8.0, 0.001, "0.5 x 16 CURRENT hp (not 40 max) = 8")

	var again := DamageInstance.new()
	again.type = DamageInstance.Type.TRUE
	again.basis = HitInstance.AmountBasis.PERCENT_CURRENT
	again.amount = 0.99
	again.target = _node
	OutcomeApplier.land_one(again, CombatWorld.live())
	assert_gt(_node.get_current_hp(), 0.0, "a fraction of current hp never reaches zero on its own")


func test_a_rebuilt_record_never_rescales_an_already_resolved_hit() -> void:
	# The authority resolves PERCENT_MAX once on its own land; the record
	# carries the resulting number and the peer's rebuilt hit must land it as
	# a FLAT amount — a second multiply against max hp would be a desync.
	var outcome := AttackOutcome.new()
	var hit := DamageInstance.new()
	hit.target = _node
	hit.attacker = _entity
	hit.basis = HitInstance.AmountBasis.PERCENT_MAX
	hit.amount = 10.0  # already resolved by the authority's land_on
	hit.effective_amount = 10.0
	outcome.hits.append(hit)

	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _graph), _graph)
	assert_eq(rebuilt.hits[0].basis, HitInstance.AmountBasis.FLAT,
			"a rebuilt hit is FLAT: its number is already HP")
	assert_almost_eq(rebuilt.hits[0].amount, 10.0, 0.001)
