extends GutTest

## TagAuraEffect (#267): AuraEffect's tag-channel sibling, plus the aura origin
## rule (source_node ?? core_location) it shares with AuraEffect. Fixture
## mirrors test_aura_effect.gd's graph/alloc/spawn setup.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 6:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)

	# Two disjoint lines: 0-1-2 and 3-4-5.
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])
	_add_edge(_nodes[3], _nodes[4])
	_add_edge(_nodes[4], _nodes[5])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)


func _spawn(core: SkillNode, owned: Array[SkillNode]) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	return ent


func _one_hop_tag_aura(tag: StringName) -> TagAuraEffect:
	var aura := TagAuraEffect.new()
	var reach := HopRangeFinder.new()
	reach.max_hops = 1
	aura.reach = reach
	aura.tag = tag
	return aura


# ── Origin rule: node-carried tag aura radiates from its own node ───────────

## The load-bearing case (#267 acceptance 3): a TagAuraEffect granted with a
## source_node that is NOT the core measures reach from that carrier node, not
## from core_location. Node 0 is the core; node 1 is the carrier, 1 hop from
## both 0 and 2. If the aura wrongly sourced from core (node 0, max_hops=1),
## node 2 (2 hops from core) would be excluded — so node 2 holding the tag is
## the proof the origin rule is doing its job.
func test_node_carried_tag_aura_radiates_from_its_carrier_not_core() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := _one_hop_tag_aura(&"marked")

	ent.grant_effect(aura, _nodes[1])   # carrier = node 1, core = node 0

	assert_true(_nodes[1].has_tag(&"marked"), "carrier itself: 0 hops")
	assert_true(_nodes[0].has_tag(&"marked"), "1 hop from carrier")
	assert_true(_nodes[2].has_tag(&"marked"),
		"1 hop from carrier — would be excluded (2 hops) if sourced from core")


## Moving the entity's core must not perturb a node-carried tag aura — its
## source is the carrier, independent of core_location.
func test_node_carried_tag_aura_survives_a_core_move() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := _one_hop_tag_aura(&"marked")
	ent.grant_effect(aura, _nodes[1])

	assert_true(_nodes[2].has_tag(&"marked"))
	_alloc.move_core(ent, _nodes[2])
	assert_true(_nodes[2].has_tag(&"marked"), "carrier unchanged; core move is irrelevant")
	assert_true(_nodes[0].has_tag(&"marked"))


# ── Origin rule regression: entity-wide (core-class) aura still sources core ─

## #267 acceptance 4, for the tag channel: an entity-wide TagAuraEffect
## (source_node null — the core-class grant path) still radiates from core,
## unchanged by the origin-rule fallback.
func test_entity_wide_tag_aura_still_radiates_from_core() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := _one_hop_tag_aura(&"blessed")

	ent.grant_effect(aura)   # no source_node → falls back to core_location

	assert_true(_nodes[0].has_tag(&"blessed"), "core itself")
	assert_true(_nodes[1].has_tag(&"blessed"), "1 hop from core")
	assert_false(_nodes[2].has_tag(&"blessed"), "2 hops from core: out of reach")


## Same regression, on plain AuraEffect (the numeric-modifier channel): a
## source_node-less grant must be byte-for-byte unchanged by the origin rule
## added to recompute() — this is what every existing test_aura_effect.gd case
## already exercises, restated here explicitly against the new code path.
func test_entity_wide_modifier_aura_still_radiates_from_core() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	var reach := HopRangeFinder.new()
	reach.max_hops = 1
	aura.reach = reach
	aura.distance_scale = FlatScale.new()
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = 5.0
	aura.modifiers = [m]
	ent.stat_board.armor.base_value = 0.0

	ent.grant_effect(aura)

	assert_almost_eq(float(_nodes[0].get_local_value(&"armor")), 5.0, 0.001)
	assert_almost_eq(float(_nodes[1].get_local_value(&"armor")), 5.0, 0.001)
	assert_almost_eq(float(_nodes[2].get_local_value(&"armor")), 0.0, 0.001)


# ── recompute lifecycle: allocation / deallocation / revoke ─────────────────

func test_tag_aura_recomputes_on_allocation_and_deallocation() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0]])
	var aura := _one_hop_tag_aura(&"marked")
	ent.grant_effect(aura, _nodes[0])
	assert_false(_nodes[1].has_tag(&"marked"), "unowned: not in the owned-scope mirror")

	_alloc.force_allocate(ent, _nodes[1])
	assert_true(_nodes[1].has_tag(&"marked"), "allocation recomputes the tag aura")

	_alloc.force_deallocate(_nodes[1])
	assert_false(_nodes[1].has_tag(&"marked"), "deallocation strips it again")


func test_revoking_the_tag_aura_clears_every_node() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1]])
	var aura := _one_hop_tag_aura(&"marked")
	var inst := ent.grant_effect(aura, _nodes[0])
	assert_true(_nodes[1].has_tag(&"marked"))

	ent.revoke_effect(inst)
	assert_false(_nodes[0].has_tag(&"marked"))
	assert_false(_nodes[1].has_tag(&"marked"))
