extends GutTest

## #511 — every [AttackPlan] survives a trip over the wire.
##
## The contract these pin, from `docs/domain/multiplayer-sync-model.md`:
## a plan's wire form carries INPUT ONLY, as ids, and rebuilds into a plan that
## names the same live objects. Resolution residue
## ([member MeleeAttackPlan.last_events] and friends) and the `_cached_*`
## target sets are rebuildable on any peer and must not ride along.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _attacker: Entity
var _hostile: Entity
var _nodes: Dictionary = {}


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	# A(0,0) - B(200,0) - C(400,0); D(600,0) is the hostile's.
	for entry in [["A", 0], ["B", 200], ["C", 400], ["D", 600]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.position = Vector2(entry[1], 0)
		_graph.add_skill_node(node)
		_nodes[entry[0]] = node
	_graph.add_edge(_nodes.A, _nodes.B)
	_graph.add_edge(_nodes.B, _nodes.C)
	_graph.add_edge(_nodes.C, _nodes.D)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container, NOT the Graph itself: entity_id is minted on entry to
	# that container (#509), and a plan naming an unminted id resolves to nothing.
	_graph.entities_container.add_child(_attacker)
	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	for key in ["A", "B", "C"]:
		alloc.force_allocate(_attacker, _nodes[key])
	_attacker.core_location = _nodes.A
	alloc.force_allocate(_hostile, _nodes.D)
	_hostile.core_location = _nodes.D


func _round_trip(plan: AttackPlan) -> AttackPlan:
	var d := plan.to_dict(_graph)
	_assert_no_live_references(d)
	return AttackPlanCodec.from_dict(d, _graph)


## The rule from `.claude/rules/multiplayer-sync.md`, asserted rather than
## trusted: no [SkillNode] and no [Entity] reference may survive `to_dict`.
## Walks nested containers, because a plan's blade list is one.
func _assert_no_live_references(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_assert_no_live_references(value[key])
		return
	if value is Array:
		for item in value:
			_assert_no_live_references(item)
		return
	assert_false(value is SkillNode, "a SkillNode reference reached the wire")
	assert_false(value is Entity, "an Entity reference reached the wire")
	assert_false(value is Resource,
			"a Resource reference reached the wire — spells cross as an id")


# ── Base fields ─────────────────────────────────────────────────────────────

func test_the_base_fields_round_trip_on_every_mode() -> void:
	for plan_class in [RangedAttackPlan, MeleeAttackPlan, MagicAttackPlan]:
		var plan: AttackPlan = plan_class.new()
		plan.attacker = _attacker
		plan.resolve_seed = 987654
		var back := _round_trip(plan)
		assert_eq(back.mode, plan.mode, "mode must survive — it is the codec's dispatch key")
		assert_eq(back.attacker, _attacker, "the attacker resolves back by entity_id")
		assert_eq(back.resolve_seed, 987654,
				"the seed rides along, or the authority cannot re-resolve and compare")


# ── Ranged ──────────────────────────────────────────────────────────────────

func test_a_ranged_plan_round_trips_its_target() -> void:
	var plan := RangedAttackPlan.new()
	plan.attacker = _attacker
	plan.target = _nodes.D
	var back := RangedAttackPlan.from_dict(plan.to_dict(_graph), _graph)
	assert_eq(back.target, _nodes.D, "the target resolves back by stable_id")


# ── Magic ───────────────────────────────────────────────────────────────────

func test_a_magic_plan_round_trips_source_target_and_spell() -> void:
	var plan := MagicAttackPlan.new()
	plan.attacker = _attacker
	plan.spell = SpellCatalog.LIGHTNING_BOLT
	plan.source = _nodes.C
	plan.target = _nodes.D
	var back := MagicAttackPlan.from_dict(plan.to_dict(_graph), _graph)
	assert_eq(back.source, _nodes.C)
	assert_eq(back.target, _nodes.D)
	assert_eq(back.spell, SpellCatalog.LIGHTNING_BOLT,
			"the spell resolves back to the SAME authored resource, not a copy")


func test_a_magic_plan_does_not_wire_its_target_cache() -> void:
	var plan := MagicAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _nodes.C
	plan.target = _nodes.D
	# Force the cache to populate, so a naive `to_dict` would have something
	# to accidentally include.
	plan._valid_targets()
	assert_false(plan._cached_valid_targets.is_empty(),
			"fixture must actually populate the cache for this to mean anything")
	var d := plan.to_dict(_graph)
	assert_eq(d.keys().size(), 6,
			"mode/attacker/seed/source/target/spell and nothing else: %s" % [d.keys()])


# ── Melee ───────────────────────────────────────────────────────────────────

func test_a_melee_plan_round_trips_its_blade() -> void:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan._on_node_left_clicked(_nodes.A)   # pivot
	plan._on_node_left_clicked(_nodes.B)   # member
	plan.blade_target = Vector2(123.0, -45.0)
	plan.swing_cw = true
	assert_eq(plan.blade_nodes, [_nodes.B] as Array[SkillNode],
			"fixture must have armed a blade for this to mean anything")

	var back := MeleeAttackPlan.from_dict(plan.to_dict(_graph), _graph)
	assert_eq(back.source, _nodes.A, "the pivot resolves back by stable_id")
	assert_eq(back.blade_nodes, [_nodes.B] as Array[SkillNode])
	assert_eq(back.blade_target, Vector2(123.0, -45.0))
	assert_true(back.swing_cw, "swing direction is an input to the sim, so it crosses")


func test_a_rebuilt_melee_plan_can_draw_its_own_blade() -> void:
	# The mirror is what `get_induced_edges` walks, and MeleePreview builds the
	# ghost blade off that. A rebuild that appended straight to `blade_nodes`
	# would round-trip every asserted field above and still draw an edgeless
	# blade — which is why this is a separate test rather than one more
	# assertion up there.
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan._on_node_left_clicked(_nodes.A)
	plan._on_node_left_clicked(_nodes.B)
	var back := MeleeAttackPlan.from_dict(plan.to_dict(_graph), _graph)
	assert_eq(back.get_induced_edges().size(), plan.get_induced_edges().size(),
			"the rebuilt blade induces the same edges as the original")
	assert_gt(back.get_induced_edges().size(), 0, "…and that is not vacuously zero")


func test_a_melee_plan_does_not_wire_its_resolution_residue() -> void:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan._on_node_left_clicked(_nodes.A)
	plan._on_node_left_clicked(_nodes.B)
	var d := plan.to_dict(_graph)
	for key in ["last_events", "last_hits", "last_trajectory", "last_pops",
			"last_live_gate"]:
		assert_false(d.has(key), "%s is resolution residue, not plan input" % key)


# ── Codec ───────────────────────────────────────────────────────────────────

func test_the_codec_refuses_an_unknown_mode_rather_than_half_building() -> void:
	assert_null(AttackPlanCodec.from_dict({}, _graph), "an empty dict is not a plan")
	assert_null(AttackPlanCodec.from_dict({"mode": 99}, _graph))
