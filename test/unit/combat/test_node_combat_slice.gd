extends GutTest

## NodeCombat.snapshot() (#498 step 2 — see docs/domain/attack-timeline.md).
## Single-node fixture: one entity, one owned node, no topology needed for
## these — see test_entity_combat_slice.gd for the multi-node / islanding
## cases.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame  # entity._ready: navigator wiring

	# force_allocate, not a bare `owned_by =` — that also mirrors the node into
	# `entity.navigator`, which is what `EntityCombat.snapshot()` walks to find
	# what to snapshot. A direct `owned_by` write (as test_node_refill.gd does)
	# leaves the mirror empty and the shadow would own nothing.
	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	await get_tree().process_frame


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _shadow_node() -> NodeCombat:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	return shadow.shadow_for(_node)


# ── Host invariant ───────────────────────────────────────────────────────────

func test_snapshot_is_hostless() -> void:
	var n := _shadow_node()
	assert_null(n.host, "a snapshotted NodeCombat must never carry a host")
	assert_true(n.is_allocated(), "the shadow still reads as owned by its shadow EntityCombat")


func test_shadow_hp_starts_from_the_real_current() -> void:
	_node.take_damage(5.0, null)
	var before := _node.get_current_hp()
	var n := _shadow_node()
	assert_eq(n.get_current_hp(), before, "a snapshot must capture real PoolStat current, not full HP")


# ── Max health is derived, not snapshotted ──────────────────────────────────

func test_max_hp_on_a_shadow_responds_to_a_mid_attack_modifier_change() -> void:
	# Targets `node_health` directly, not `constitution` feeding it through
	# node_health_scaling's formula — a formula modifier's cross-stat
	# reactivity is wired via runtime signal connections
	# (StatModifier._on_source_changed), and Resource.duplicate() does not
	# preserve signal connections. That's a pre-existing StatBoard.duplicate()
	# limitation, not something #498 introduces or needs to fix: the ratchet
	# pull below reads bins.get_value() directly off the target stat, which is
	# exactly why an ADD_BASE landing straight on node_health still updates
	# with no reactive wiring involved.
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var n: NodeCombat = shadow.shadow_for(_node)
	var before := n.get_max_hp()

	var mod := StatModifier.new()
	mod.stat_id = &"node_health"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 50.0
	shadow.board().add_modifier(mod)

	var after := n.get_max_hp()
	assert_gt(after, before, "max HP must move with a modifier added mid-\"attack\", not stay frozen")

	# The real node (and a fresh read of it) is untouched by the shadow's
	# modifier — the two boards are independent duplicates.
	assert_eq(_node.get_max_hp(), before, "the shadow's modifier must not leak onto the real board")


func test_shadow_take_damage_never_mutates_the_real_node() -> void:
	var real_hp_before := _node.get_current_hp()
	var n := _shadow_node()
	n.take_damage(1.0, null)
	assert_eq(_node.get_current_hp(), real_hp_before, "a shadow hit must not touch the real node's HP")
