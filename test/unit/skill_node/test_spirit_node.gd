extends GutTest

## An aspect spirit: one fixed +1 `<aspect>_aspect` offer, tinted by the aspect
## (gray and concealed for the mystery variant), claimed once through the
## ordinary relic path. See docs/domain/spirits.md.

const _SPIRIT := preload("res://skill_node/keystone/instances/spirit_node.tscn")
const _MYSTERY := preload("res://skill_node/keystone/instances/mystery_spirit_node.tscn")
const _POISON := preload("res://identity/defs/poison.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _DUST_SCENE := preload("res://skill_node/addons/defs/skill_dust_addon.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	# Offline: no applier, so a claim runs its round inline.
	var loot := LootSystem.new()
	loot.skill_dust_scene = _DUST_SCENE
	add_child_autofree(loot)
	await get_tree().process_frame


func _spirit(scene: PackedScene, at: Vector2, fixed: Identity = null) -> SpiritNode:
	var s := scene.instantiate() as SpiritNode
	s.fixed_aspect = fixed
	s.position = at
	_graph.add_skill_node(s)
	return s


func _entity(label: String, at: Vector2) -> Entity:
	var core: SkillNode = _NODE_SCENE.instantiate()
	core.position = at
	_graph.add_skill_node(core)
	var e: Entity = autofree(Entity.new())
	e.display_name = label
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	e.core_location = core
	return e


func _aspect_grants(e: Entity, stat_id: StringName) -> float:
	var total := 0.0
	for m in e.core_modifiers:
		if m.stat_id == stat_id:
			total += m.value
	return total


func test_a_poison_spirit_offers_one_plus_one_poison_aspect() -> void:
	var s := _spirit(_SPIRIT, Vector2(300, 0), _POISON)
	var dust := s.get_dust()
	assert_not_null(dust, "the spirit carries its relic")
	if dust == null:
		return
	assert_eq(dust.candidates.size(), 1, "exactly one candidate")
	assert_eq(dust.candidates[0].stat_id, &"poison_aspect")
	assert_eq(dust.candidates[0].operation, StatModifier.Operation.ADD_BASE)
	assert_eq(dust.candidates[0].value, 1.0)
	assert_eq(dust.weights, [1.0] as Array[float])
	assert_eq(dust.rounds, 1)
	assert_eq(dust.gold_color, _POISON.tint, "the dust wears the aspect's tint")
	assert_false(dust.conceal_offer)


func test_the_first_allocator_absorbs_it_and_a_second_gets_nothing() -> void:
	var s := _spirit(_SPIRIT, Vector2(300, 0), _POISON)
	var first := _entity("First", Vector2(0, 0))
	var second := _entity("Second", Vector2(600, 0))
	await get_tree().process_frame

	s.owned_by = first
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_aspect_grants(first, &"poison_aspect"), 1.0, "+1 poison_aspect in the core register")
	assert_null(s.get_dust(), "the node keeps no relic afterwards")

	s.owned_by = null
	s.owned_by = second
	await get_tree().process_frame
	assert_eq(_aspect_grants(second, &"poison_aspect"), 0.0, "a second allocator gets nothing")


func test_the_roll_is_a_function_of_position() -> void:
	var a := _spirit(_SPIRIT, Vector2(123, 456))
	var b := _spirit(_SPIRIT, Vector2(123, 456))
	assert_not_null(a.aspect, "a spirit with no fixed aspect rolls one")
	assert_eq(a.aspect, b.aspect, "same position, same aspect")
	assert_eq(a.get_dust().candidates[0].stat_id, StringName(String(a.aspect.id) + "_aspect"))


func test_every_pooled_aspect_names_a_real_stat() -> void:
	var s := _spirit(_SPIRIT, Vector2.ZERO)
	assert_eq(s.aspects.size(), 12, "the roll pool is the 12 aspects")
	for a in s.aspects:
		assert_not_null(StatRegistry.get_def(StringName(String(a.id) + "_aspect")), "%s_aspect exists" % a.id)


func test_a_mystery_spirit_is_gray_and_conceals_its_offer() -> void:
	var s := _spirit(_MYSTERY, Vector2(300, 0))
	var dust := s.get_dust()
	assert_true(s.reveal_on_claim)
	assert_eq(dust.gold_color, s.mystery_color, "gray until claimed")
	assert_true(dust.get_tooltip_modifiers().is_empty(), "the tooltip hides the aspect")
	assert_eq(dust.candidates.size(), 1, "but the offer is still there")
