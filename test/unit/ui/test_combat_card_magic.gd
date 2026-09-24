extends GutTest

## #1029 — the Magic card's Reach row has two tiers: with no spell selected it
## DESCRIBES the caster's `cast_range_hops` pipeline (the fold as text, via
## `Stat.resolve_with([]).describe()`); with a spell selected it shows the
## number `SpellRangeRules.reach` answers, never the raw authored `max_hops`.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _MAGIC_SCENE := preload("res://ui/hud/combat_readout/combat_card_magic.tscn")


func _spawn_entity(graph: Graph) -> Entity:
	var entity: Entity = _ENTITY_SCENE.instantiate()
	entity.stat_board = TestBoards.flat_entity_board()
	graph.entities_container.add_child(entity)
	return entity


func _mod(id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


func _spell_with_hops(hops: float) -> SpellDef:
	var spell := SpellDef.new()
	spell.propagation = PropagationConfig.new()
	spell.propagation.max_hops = hops
	return spell


## Arranges the acceptance board: `cast_range_hops` carrying +3 ADD_BASE and
## +50% INCREASE, bound to a fresh magic card. Returns [card, reach value label].
func _bound_card() -> Array:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity := _spawn_entity(graph)
	var reach: Stat = entity.stat_board.get_stat(&"cast_range_hops")
	reach.add_modifier(_mod(&"cast_range_hops", StatModifier.Operation.ADD_BASE, 3.0))
	reach.add_modifier(_mod(&"cast_range_hops", StatModifier.Operation.INCREASE, 50.0))
	var card: CombatCardMagic = _MAGIC_SCENE.instantiate()
	add_child_autofree(card)
	card.bind(entity)
	return [card, card.get_node("%ReachRow").get_node("%Value")]


func test_no_spell_reach_row_describes_the_cast_range_pipeline() -> void:
	var pair := _bound_card()
	var value: Label = pair[1]
	assert_eq(value.text, "(X+3) × 1.5", "no spell: the row describes the fold, not a zero")


func test_selected_spell_reach_row_shows_the_rules_number_not_authored_hops() -> void:
	var pair := _bound_card()
	var card: CombatCardMagic = pair[0]
	var value: Label = pair[1]
	card._spell = _spell_with_hops(3)
	assert_eq(value.text, "9 hops", "spell: int((3+3) × 1.5) through SpellRangeRules.reach")


func test_deselecting_the_spell_returns_the_row_to_the_describe_tier() -> void:
	var pair := _bound_card()
	var card: CombatCardMagic = pair[0]
	var value: Label = pair[1]
	card._spell = _spell_with_hops(3)
	card._spell = null
	assert_eq(value.text, "(X+3) × 1.5", "deselect: back to the text tier")


func test_selected_inf_hop_spell_reach_row_reads_infinity() -> void:
	var pair := _bound_card()
	var card: CombatCardMagic = pair[0]
	var value: Label = pair[1]
	card._spell = _spell_with_hops(INF)
	assert_eq(value.text, "∞ hops", "an unbounded walk reads as infinity, not a number")
