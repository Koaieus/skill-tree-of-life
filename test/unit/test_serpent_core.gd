extends GutTest

## #39: the Serpent — two auras riding the same `armor` stat (plus damage),
## one keyed to hop distance (grows with topological distance) and one to
## euclidean distance (shrinks with spatial distance). `Array[Effect]`
## composes them without any `CompositeEffect` — see
## docs/domain/effect-system.md's Auras table.
##
## #990: the mechanic tests below run on a HAND-BUILT board and a hand-built
## CoreClass of the same SHAPE as `serpent_core.tres` (a hop-keyed
## ProportionalScale aura and a euclid-keyed ProportionalScale aura, both
## riding armor plus a damage composite) — never magnitudes read from the
## authored resource. `serpent_core.tres` itself gets one shape-only test at
## the bottom.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SERPENT := preload("res://entity/core/serpent_core.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]
var _entity: Entity


## Test-chosen stand-in for `serpent_core.tres`'s two-aura shape: a hop-keyed
## ProportionalScale granting +1 armor/hop (plus a +1/hop damage composite),
## and a euclid-keyed ProportionalScale penalizing -1 armor per 200px (plus a
## matching damage composite) — same per_unit ratio as the authored class
## (0.005/px == -1 at 200px) so the fixture's "1 hop == 100px" line produces
## the same round numbers the old pinned test asserted, now chosen by the
## test rather than read off the .tres.
func _build_serpent_like_core() -> CoreClass:
	var hop_armor := StatModifier.new()
	hop_armor.stat_id = &"armor"
	hop_armor.operation = StatModifier.Operation.ADD_BONUS
	hop_armor.value = 1.0
	var hop_damage := CompositeStatModifier.new()
	hop_damage.children = [_dmg_mod(&"blade_damage", StatModifier.Operation.ADD_BASE, 1.0)]
	var hop_aura := AuraEffect.new()
	hop_aura.metric = HopMetric.new()
	hop_aura.distance_scale = ProportionalScale.new()
	hop_aura.discard = AuraEffect.Discard.ZERO # skip only ~0, negatives land too — same as serpent_core.tres
	hop_aura.modifiers = [hop_armor, hop_damage]

	var euclid_armor := StatModifier.new()
	euclid_armor.stat_id = &"armor"
	euclid_armor.operation = StatModifier.Operation.ADD_BONUS
	euclid_armor.value = -1.0
	var euclid_scale := ProportionalScale.new()
	euclid_scale.per_unit = 0.005
	var euclid_damage := CompositeStatModifier.new()
	euclid_damage.children = [_dmg_mod(&"blade_damage", StatModifier.Operation.INCREASE, -0.5)]
	var euclid_aura := AuraEffect.new()
	euclid_aura.metric = EuclideanMetric.new()
	euclid_aura.distance_scale = euclid_scale
	euclid_aura.discard = AuraEffect.Discard.ZERO
	euclid_aura.modifiers = [euclid_armor, euclid_damage]

	var core := CoreClass.new()
	core.modifiers = []
	core.effects = [hop_aura, euclid_aura]
	return core


func _dmg_mod(stat_id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	# A straight line, so hop distance (chain index) and euclidean distance
	# (100px per hop) both grow together from either end — exactly the
	# "same node, both metrics" case the class composes.
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])
	_graph.add_edge(_nodes[2], _nodes[3])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new()) as Entity
	_entity.display_name = "Coil"
	_entity.stat_board = TestBoards.flat_entity_board()
	_entity.core_class = _build_serpent_like_core()
	_graph.add_child(_entity)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	_alloc.force_allocate(_entity, _nodes[1])
	_alloc.force_allocate(_entity, _nodes[2])
	_alloc.force_allocate(_entity, _nodes[3])
	_entity.stat_board.armor.base_value = 0.0


func test_dual_metric_auras_sum_on_the_same_stat() -> void:
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "core: both scales are 0")
	# 1 hop / 100px: +1 hop buff, -0.5 euclid penalty = 0.5 → 0: armor is
	# INT and the merged local read floors once (#890/#895).
	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001)
	# 2 hops / 200px: +2 hop buff, -1.0 euclid penalty.
	assert_almost_eq(_armor(_nodes[2]), 1.0, 0.001)


## move_core only hops to an *adjacent* owned node (AllocationSystem's
## contract) — node0 → node1, not a multi-hop teleport.
func test_core_move_recomputes_both_auras() -> void:
	assert_true(_alloc.move_core(_entity, _nodes[1]), "adjacent move must succeed")

	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001, "new core: untouched")
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "1 hop / 100px from new core (0.5 floors to 0)")
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001, "1 hop / 100px on the other side (0.5 floors to 0)")
	assert_almost_eq(_armor(_nodes[3]), 1.0, 0.001, "2 hops / 200px from new core")


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


## #623 shipped-content regression guard: a composite (blade/spell/ranged
## damage bundled together) inside BOTH auras must scale with distance too,
## not just the plain `armor` modifier riding alongside it — `grant_at` moving
## only the outer (vestigial) handle was the bug. Relative comparisons only
## (#719): the property is "moves with distance", not a specific number.
func test_composite_children_scale_with_distance_not_just_armor() -> void:
	var blade_1 := float(_nodes[1].get_local_value(&"blade_damage"))
	var blade_2 := float(_nodes[2].get_local_value(&"blade_damage"))
	var blade_3 := float(_nodes[3].get_local_value(&"blade_damage"))

	assert_ne(blade_1, blade_2, "blade_damage must move with distance, not sit at one flat value")
	assert_ne(blade_2, blade_3)
	# Same shape as armor: on this straight-line fixture (100px/hop) the hop
	# buff's growing ADD_BASE dominates the euclid penalty's much smaller
	# INCREASE malus, so blade_damage rises with distance too.
	assert_gt(blade_2, blade_1, "further node: bigger hop-buff contribution")
	assert_gt(blade_3, blade_2)


# ── serpent_core.tres shape (#990) ──────────────────────────────────────────

## No magnitudes: checks the authored `.tres` carries two auras on
## complementary metrics (hop vs euclid), both riding `armor`, never a number
## that would red on a routine retune.
func test_serpent_core_tres_shape() -> void:
	assert_eq(_SERPENT.effects.size(), 2, "two auras — the hop buff and the euclid penalty")
	var metrics: Array = []
	for e in _SERPENT.effects:
		assert_true(e is AuraEffect, "both effects are auras")
		var aura := e as AuraEffect
		metrics.append(aura.metric.get_script())
		var armor_leaf: StatModifier = null
		for m in aura.modifiers:
			if m is StatModifier and (m as StatModifier).stat_id == &"armor":
				armor_leaf = m as StatModifier
		assert_not_null(armor_leaf, "each aura carries a plain armor modifier")
	assert_true(metrics.has(HopMetric), "one aura is keyed to hops")
	assert_true(metrics.has(EuclideanMetric), "the other is keyed to euclidean space")
