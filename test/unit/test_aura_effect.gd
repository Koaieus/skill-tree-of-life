extends GutTest

## AuraEffect (#4 phase 2): range-based local buffs that re-derive whenever the
## world moves. Uses real `force_allocate` (not raw `owned_by =`) so the entity's
## navigator mirror is actually populated — an aura measuring hops over an empty
## mirror silently buffs nothing.

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
		# Must go through add_skill_node / add_edge: adding straight to the
		# container skips `node_added`, leaving the Graph's Navigator empty.
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
	ent.stat_board.armor.base_value = 0.0
	return ent


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


func _armor_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


## Flat +5 armor within 1 hop of the core.
func _bulwark() -> AuraEffect:
	var aura := AuraEffect.new()
	var reach := HopRangeFinder.new()
	reach.max_hops = 1
	aura.reach = reach
	aura.distance_scale = FlatScale.new()
	aura.modifiers = [_armor_mod(5.0)]
	return aura


# ── Reach gating ────────────────────────────────────────────────────────────

func test_aura_buffs_nodes_in_reach_only() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	ent.grant_effect(_bulwark())

	assert_almost_eq(_armor(_nodes[0]), 5.0, 0.001, "core is in its own aura")
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001, "1 hop away: buffed")
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001, "2 hops away: out of reach")


## Initial population happens on grant, not on the first core move. The opening
## core placement never passes through `move_core`.
func test_aura_populates_on_grant() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1]])
	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001)
	ent.grant_effect(_bulwark())
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001, "granted → immediately applied")


## The remove path is where the bugs live. Write it first.
func test_core_moves_away_and_node_loses_the_buff() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	ent.grant_effect(_bulwark())
	assert_almost_eq(_armor(_nodes[0]), 5.0, 0.001)
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001)

	_alloc.move_core(ent, _nodes[1])
	assert_almost_eq(_armor(_nodes[2]), 5.0, 0.001, "now 1 hop from the core")

	_alloc.move_core(ent, _nodes[2])
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "core left; node 0 must lose the buff")
	assert_almost_eq(_armor(_nodes[2]), 5.0, 0.001)


func test_allocating_a_node_in_reach_buffs_it() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0]])
	ent.grant_effect(_bulwark())
	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001, "unowned: not in the owned-scope mirror")

	_alloc.force_allocate(ent, _nodes[1])
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001, "allocation recomputes the aura")

	_alloc.force_deallocate(_nodes[1])
	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001, "deallocation strips it again")


func test_revoking_the_aura_clears_every_node() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1]])
	var inst := ent.grant_effect(_bulwark())
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001)
	ent.revoke_effect(inst)
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001)
	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001)


# ── Production spawn path ───────────────────────────────────────────────────

## The one that matters: mimic `GameRoot.spawn_entity` exactly — assign
## `core_class`, add to tree (so `_ready` grants its effects), THEN force_allocate
## and set `core_location`. No manual `grant_effect`.
##
## The aura's `_on_granted` runs during `_ready`, when core_location is still null
## and the mirror is empty. Nothing would ever re-fire it unless the core_location
## setter itself dispatches `_on_core_moved` — `AllocationSystem.move_core` is not
## on this path. Without that, a core-class aura buffs nothing, forever, and every
## hand-ordered test still passes.
func test_core_class_aura_populates_via_the_spawn_entity_order() -> void:
	var core_class := CoreClass.new()
	core_class.effects = [_bulwark()]

	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "Spawned"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	ent.core_class = core_class
	_graph.add_child(ent)                       # _ready → core_class.apply → grant
	await get_tree().process_frame

	_alloc.force_allocate(ent, _nodes[0])       # core node
	ent.core_location = _nodes[0]               # ← must re-derive the aura
	ent.stat_board.armor.base_value = 0.0
	_alloc.force_allocate(ent, _nodes[1])

	assert_almost_eq(_armor(_nodes[0]), 5.0, 0.001,
		"core-class aura must populate on the real spawn path")
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001, "1 hop from core: buffed")
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001, "unowned: untouched")


## Assigning core_location is what re-derives the aura — not move_core, which is
## only one caller of the setter.
func test_assigning_core_location_directly_recomputes_the_aura() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	ent.grant_effect(_bulwark())
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001)

	ent.core_location = _nodes[2]               # bypasses AllocationSystem entirely
	assert_almost_eq(_armor(_nodes[2]), 5.0, 0.001)
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "old core position dropped")


# ── Shared-resource state trap ──────────────────────────────────────────────

## An AuraEffect .tres is shared across every entity of its class. A buffed-set
## dict on the resource would have one entity's recompute wipe the other's. The
## existing "same .tres on two entities" duplication test would NOT catch this.
func test_two_entities_share_one_aura_resource_without_interfering() -> void:
	var aura := _bulwark()
	var a: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var b: Entity = await _spawn(_nodes[3], [_nodes[3], _nodes[4], _nodes[5]])
	a.grant_effect(aura)
	b.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[4]), 5.0, 0.001)

	# A's core moves. B's aura must be untouched.
	_alloc.move_core(a, _nodes[1])
	assert_almost_eq(_armor(_nodes[4]), 5.0, 0.001, "B's buffed set survived A's recompute")
	assert_almost_eq(_armor(_nodes[3]), 5.0, 0.001)


# ── Scales ──────────────────────────────────────────────────────────────────

## The Ninja: -1 armor per hop from core, unbounded reach, going negative.
## Proves DistanceScale is direction-agnostic — the name "falloff" would lie here.
func test_proportional_scale_deepens_a_debuff_with_distance() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	aura.reach = null                       # flood the owned subgraph
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.modifiers = [_armor_mod(-1.0)]
	ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "core: scale 0, untouched")
	assert_almost_eq(_armor(_nodes[1]), -1.0, 0.001)
	assert_almost_eq(_armor(_nodes[2]), -2.0, 0.001, "magnitude grows with distance")


## Negative armor amplifies incoming damage — the Ninja's actual cost.
func test_ninja_debuff_amplifies_damage_through_mitigation() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	ent.stat_board.min_damage_taken.base_value = 0.0
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.modifiers = [_armor_mod(-1.0)]
	ent.grant_effect(aura)

	var raw := DamageInstance.new()
	raw.amount = 5.0
	assert_almost_eq(Mitigation.apply(raw, _nodes[2]), 7.0, 0.001,
		"armor -2 turns a 5-damage hit into 7")


func test_shell_scale_buffs_only_the_ring() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var shell := ShellScale.new()
	shell.shell_distance = 2.0
	shell.near_scale = 0.5
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = shell
	aura.modifiers = [_armor_mod(10.0)]
	ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "2 hops inside the shell: nothing")
	assert_almost_eq(_armor(_nodes[1]), 5.0, 0.001, "near-shell: half")
	assert_almost_eq(_armor(_nodes[2]), 10.0, 0.001, "at the shell: full")


## The Serpent: two auras, one per metric, summing additively on one stat.
## Rising hop buff, rising euclidean penalty. No CompositeEffect needed.
func test_serpent_dual_metric_auras_sum_additively() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])

	var hop_buff := AuraEffect.new()
	hop_buff.metric = HopMetric.new()
	hop_buff.distance_scale = ProportionalScale.new()   # +1 per hop
	hop_buff.modifiers = [_armor_mod(1.0)]

	var euclid_penalty := AuraEffect.new()
	euclid_penalty.metric = EuclideanMetric.new()
	var per_px := ProportionalScale.new()
	per_px.per_unit = 0.005                             # -0.005 per pixel
	euclid_penalty.distance_scale = per_px
	euclid_penalty.modifiers = [_armor_mod(-1.0)]

	ent.grant_effect(hop_buff)
	ent.grant_effect(euclid_penalty)

	# Node 2: 2 hops out, 200px out → +2 - 1.0 = +1.0
	assert_almost_eq(_armor(_nodes[2]), 1.0, 0.001)
	# Node 1: 1 hop, 100px → +1 - 0.5 = +0.5
	assert_almost_eq(_armor(_nodes[1]), 0.5, 0.001)


# ── Composite modifiers (#623) ──────────────────────────────────────────────

## A two-leaf bundle. `_composite_pair` rather than reusing `_armor_mod` twice:
## the bug is specifically about a CompositeStatModifier's CHILDREN, which a
## plain-modifier aura (armor above) cannot exercise at all.
func _composite_pair(a_id: StringName, a_value: float, b_id: StringName, b_value: float) -> CompositeStatModifier:
	var c := CompositeStatModifier.new()
	var la := StatModifier.new()
	la.stat_id = a_id
	la.operation = StatModifier.Operation.ADD_BONUS
	la.value = a_value
	var lb := StatModifier.new()
	lb.stat_id = b_id
	lb.operation = StatModifier.Operation.ADD_BONUS
	lb.value = b_value
	c.children = [la, lb]
	return c


## Failing on master: `grant_scaled` scaled the vestigial OUTER composite
## handle after `grant()` had already flattened + bound each CHILD, so every
## leaf applied at full authored strength regardless of distance. Bridges the
## fixture's two disjoint 3-node lines into one 6-node chain so hop 1 and hop 3
## both exist under one entity's ownership.
func test_composite_children_scale_with_aura_distance() -> void:
	_add_edge(_nodes[2], _nodes[3])
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])

	var finder := HopRangeFinder.new()
	finder.max_hops = 4   # bound > the hop-3 node under test, so neither hop hits scale 0
	var aura := AuraEffect.new()
	aura.reach = finder
	aura.distance_scale = LinearScale.new()   # real falloff: 1.0 at the source, 0.0 at the bound
	aura.modifiers = [_composite_pair(&"blade_damage", 10.0, &"spell_damage", 10.0)]

	var blade_base_1 := float(_nodes[1].get_local_value(&"blade_damage"))
	var blade_base_3 := float(_nodes[3].get_local_value(&"blade_damage"))
	var spell_base_1 := float(_nodes[1].get_local_value(&"spell_damage"))
	var spell_base_3 := float(_nodes[3].get_local_value(&"spell_damage"))

	ent.grant_effect(aura)

	var blade_delta_1 := float(_nodes[1].get_local_value(&"blade_damage")) - blade_base_1
	var blade_delta_3 := float(_nodes[3].get_local_value(&"blade_damage")) - blade_base_3
	var spell_delta_1 := float(_nodes[1].get_local_value(&"spell_damage")) - spell_base_1
	var spell_delta_3 := float(_nodes[3].get_local_value(&"spell_damage")) - spell_base_3

	assert_gt(blade_delta_1, blade_delta_3, "closer hop must scale HIGHER than a farther one")
	assert_gt(spell_delta_1, spell_delta_3)
	assert_lt(blade_delta_1, 10.0, "scaled below the authored child value at any nonzero hop")
	assert_lt(spell_delta_1, 10.0)
	assert_gt(blade_delta_3, 0.0, "still applied at hop 3 — not skipped as a zero scale")
	assert_gt(spell_delta_3, 0.0)


## Acceptance 4: `grant_scaled` must duplicate before it ever touches a leaf's
## `value` — the authored `.tres` sub-resources a CoreClass's auras reference
## are shared, so a live mutation on them would corrupt every entity of that
## class, not just the one being scaled.
func test_grant_scaled_never_mutates_the_authored_composite() -> void:
	var authored := _composite_pair(&"blade_damage", 10.0, &"spell_damage", 10.0)
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.modifiers = [authored]
	ent.grant_effect(aura)

	assert_eq((authored.children[0] as StatModifier).value, 10.0, "authored child 0 untouched")
	assert_eq((authored.children[1] as StatModifier).value, 10.0, "authored child 1 untouched")


## Acceptance 5: the same scaling must hold when the aura RECOMPUTES against a
## SHADOW slice — attack resolution's actual path (docs/domain/attack-timeline.md)
## — not only the live entity. Forces a real recompute via `dispatch`, the same
## call `EntityCombat.apply_cascade`'s `_on_node_deallocated` makes, rather than
## just reading a snapshot's cloned bins (which would prove nothing about
## `grant_scaled` itself).
func test_composite_children_scale_correctly_when_an_aura_recomputes_on_a_shadow() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.modifiers = [_composite_pair(&"blade_damage", 2.0, &"spell_damage", 2.0)]
	ent.grant_effect(aura)

	var live_blade := float(_nodes[2].get_local_value(&"blade_damage"))
	var live_spell := float(_nodes[2].get_local_value(&"spell_damage"))

	var shadow := ent.get_combat().snapshot()
	shadow.dispatch(&"_on_node_allocated", [_nodes[2], false])
	var shadow_node := shadow.world().combat_for(_nodes[2])

	assert_almost_eq(float(shadow_node.get_local_value(&"blade_damage")), live_blade, 0.001,
			"a composite aura re-granted ON a shadow must scale its children exactly like the live grant")
	assert_almost_eq(float(shadow_node.get_local_value(&"spell_damage")), live_spell, 0.001)
	shadow.free_shadow()


# ── gather() vs in_range() ──────────────────────────────────────────────────

## The perf fix: one BFS, same answer as N× in_range. Scoped to the GLOBAL mirror
## — the owned-scope equivalence deliberately does NOT hold, since in_range
## routes through the global navigator.
func test_hop_gather_matches_in_range_on_the_global_mirror() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0]])
	var finder := HopRangeFinder.new()
	finder.max_hops = 2

	var gathered := finder.gather(_nodes[0], _graph.navigator)
	for n in _nodes:
		var predicted: bool = (n == _nodes[0]) or finder.in_range(ent, _nodes[0], n)
		assert_eq(gathered.has(n), predicted, "gather and in_range disagree on %s" % n.name)

	assert_almost_eq(gathered[_nodes[0]], 0.0, 0.001)
	assert_almost_eq(gathered[_nodes[2]], 2.0, 0.001, "gather reports the distance too")


## Owned scope must not shortcut through unowned territory. Node 2 is 2 hops away
## in the graph, but if the entity doesn't own node 1 there is no owned path.
func test_owned_scope_does_not_reach_through_unowned_nodes() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[2]])
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = FlatScale.new()
	aura.modifiers = [_armor_mod(5.0)]
	ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[0]), 5.0, 0.001)
	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001,
		"unreachable over owned edges — node 1 is not owned")
