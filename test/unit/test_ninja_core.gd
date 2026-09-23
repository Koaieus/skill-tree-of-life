extends GutTest

## #39: the Ninja — a positive attribute grant, a bundled tax on Wisdom, and a
## bounded core aura that makes nearby owned nodes hit harder (blade damage).
## Reach is deliberately bounded (unlike the Serpent's unbounded auras): the
## Ninja is rewarded for staying compact, not for sprawling.
##
## #990: the mechanic tests below run on a HAND-BUILT board and a hand-built
## CoreClass carrying test-chosen modifiers/effects of the same SHAPE as
## `ninja_core.tres` (positive ADD_BASE attributes, a Wisdom tax, a falling
## linear aura on blade_damage) — never magnitudes read from the authored
## resource. `ninja_core.tres` itself gets one shape-only test at the bottom,
## the #719 precedent is test_dexterity_pool.gd's test_dexterity_pool_shape.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NINJA := preload("res://entity/core/ninja_core.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]
var _entity: Entity
var _core: CoreClass
## skill_points.claim(1) runs per force_allocate below, growing the pool cap by
## 1 per owned node — a fixture side effect, not the class's own stat.
## Captured right after core_class.apply() so test_statline reads the class's
## own delta.
var _wisdom_before_allocation: float


## Test-chosen stand-in for `ninja_core.tres`'s bundle: a positive attribute
## grant plus a Wisdom tax (mod_budget_pack's shape), on a CompositeStatModifier
## so the same "flatten before apply" path the real class rides gets exercised.
func _build_ninja_like_core() -> CoreClass:
	var str_mod := StatModifier.new()
	str_mod.stat_id = &"strength"
	str_mod.operation = StatModifier.Operation.ADD_BASE
	str_mod.value = 7.0
	var dex_mod := StatModifier.new()
	dex_mod.stat_id = &"dexterity"
	dex_mod.operation = StatModifier.Operation.ADD_BASE
	dex_mod.value = 7.0
	var int_mod := StatModifier.new()
	int_mod.stat_id = &"intelligence"
	int_mod.operation = StatModifier.Operation.ADD_BASE
	int_mod.value = 7.0
	var wis_tax := StatModifier.new()
	wis_tax.stat_id = &"wisdom"
	wis_tax.operation = StatModifier.Operation.MULTIPLY
	wis_tax.value = 0.5

	var blade_mod := StatModifier.new()
	blade_mod.stat_id = &"blade_damage"
	blade_mod.operation = StatModifier.Operation.ADD_BASE
	blade_mod.value = 5.0
	var reach := HopRangeFinder.new()
	reach.max_hops = 5
	var aura := AuraEffect.new()
	aura.reach = reach
	aura.distance_scale = LinearScale.new() # falling by default
	aura.modifiers = [blade_mod]

	var core := CoreClass.new()
	core.modifiers = [str_mod, dex_mod, int_mod, wis_tax]
	core.effects = [aura]
	return core


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_nodes = []
	for i in 7:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	# A straight line: 0-1-2-3-4-5-6, so hop distance == chain index. Long
	# enough to reach the aura's 5-hop boundary AND one node past it.
	for i in 6:
		_graph.add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_core = _build_ninja_like_core()
	_entity = autofree(Entity.new()) as Entity
	_entity.display_name = "Phantom"
	_entity.stat_board = TestBoards.flat_entity_board()
	_entity.core_class = _core
	_graph.add_child(_entity)  # _ready → core_class.apply() grants modifiers + aura
	await get_tree().process_frame
	_wisdom_before_allocation = _entity.stat_board.wisdom.get_value()

	# Mirror GameRoot.spawn_entity's order: force_allocate the core node, THEN
	# assign core_location (the setter is what re-derives the aura — see
	# test_aura_effect.gd's test_core_class_aura_populates_via_the_spawn_entity_order).
	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	for i in 6:
		_alloc.force_allocate(_entity, _nodes[i + 1])


func test_statline() -> void:
	var b := _entity.stat_board
	assert_almost_eq(b.strength.get_value(), b.strength.base_value + 7.0, 0.001, "base + class ADD_BASE")
	assert_almost_eq(b.dexterity.get_value(), b.dexterity.base_value + 7.0, 0.001)
	assert_almost_eq(b.intelligence.get_value(), b.intelligence.base_value + 7.0, 0.001)
	# Content invariant, not a value pin (#719): what must survive a retune of
	# the tax's rate is that a bundled cost REACHES the board at all.
	assert_lt(_wisdom_before_allocation, b.wisdom.base_value,
			"the class's bundled tax still bites: halved from the board's own base")


## Isolates the aura's own contribution from the class's baseline blade_damage,
## which the local read still carries via entity-board pass-through. Linear
## falloff over 5 hops — full value at the core, zero at the hop boundary
## (`value == max_hops`, #895) — and staying zero one hop past it.
func test_aura_is_intense_at_core_and_fades_to_zero_by_five_hops() -> void:
	var baseline: float = _entity.stat_board.blade_damage.get_value()
	assert_almost_eq(_local_blade(_nodes[0]) - baseline, 5.0, 0.001, "core: full aura")
	assert_almost_eq(_local_blade(_nodes[1]) - baseline, 4.0, 0.001, "1 hop: 80% aura")
	assert_almost_eq(_local_blade(_nodes[2]) - baseline, 3.0, 0.001, "2 hops: 60% aura")
	assert_almost_eq(_local_blade(_nodes[5]) - baseline, 0.0, 0.001, "5 hops: scale hits zero")
	assert_almost_eq(_local_blade(_nodes[6]) - baseline, 0.0, 0.001, "6 hops: out of reach entirely")


## move_core only hops to an *adjacent* owned node (AllocationSystem's
## contract) — node0 → node1, not a multi-hop teleport.
func test_core_moving_drops_the_buff_on_nodes_left_behind() -> void:
	var baseline: float = _entity.stat_board.blade_damage.get_value()
	assert_almost_eq(_local_blade(_nodes[5]) - baseline, 0.0, 0.001, "5 hops from the old core: scale hits zero")

	assert_true(_alloc.move_core(_entity, _nodes[1]), "adjacent move must succeed")

	assert_almost_eq(_local_blade(_nodes[1]) - baseline, 5.0, 0.001, "now the core")
	assert_almost_eq(_local_blade(_nodes[0]) - baseline, 4.0, 0.001, "1 hop from the new core: 80% aura")
	assert_almost_eq(_local_blade(_nodes[2]) - baseline, 4.0, 0.001, "1 hop from the new core: 80% aura")
	assert_almost_eq(_local_blade(_nodes[6]) - baseline, 0.0, 0.001, "5 hops from the new core: scale hits zero")


func _local_blade(n: SkillNode) -> float:
	return float(n.get_local_value(&"blade_damage"))


# ── ninja_core.tres shape (#990) ────────────────────────────────────────────

## No magnitudes: the authored `.tres` is checked for its IDENTITY — which
## stats it touches, which direction, how many auras — never for a number that
## would red on a routine retune. Flatten the composite packs first (the
## attribute baseline and the budget pack are both CompositeStatModifier).
func test_ninja_core_tres_shape() -> void:
	var leaves: Array[StatModifier] = []
	for m in _NINJA.modifiers:
		if m is CompositeStatModifier:
			leaves.append_array((m as CompositeStatModifier).flatten())
		else:
			leaves.append(m)
	var by_stat: Dictionary = {}
	for leaf in leaves:
		by_stat[leaf.stat_id] = leaf

	for stat_id in [&"strength", &"dexterity", &"intelligence"]:
		var leaf: StatModifier = by_stat[stat_id]
		assert_eq(leaf.operation, StatModifier.Operation.ADD_BASE, "%s is a flat attribute grant" % stat_id)
		assert_gt(leaf.value, 0.0, "%s adds, never subtracts" % stat_id)

	var wis_leaf: StatModifier = by_stat[&"wisdom"]
	assert_eq(wis_leaf.operation, StatModifier.Operation.MULTIPLY, "the bundled cost is a Wisdom multiplier")
	assert_true(wis_leaf.value < 1.0, "…and it taxes, never boosts")

	assert_eq(_NINJA.effects.size(), 2, "the strike aura plus the brittle-armor debuff")
	var strike: AuraEffect = null
	for e in _NINJA.effects:
		if e is AuraEffect and (e as AuraEffect).reach is HopRangeFinder:
			strike = e as AuraEffect
	assert_not_null(strike, "one aura is bounded by hop reach — the compact-reward core aura")
	assert_true((strike.reach as HopRangeFinder).max_hops > 0, "the reach is finite, not global")
