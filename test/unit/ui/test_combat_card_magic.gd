extends GutTest

## The Magic card reads the CASTER, never the cast (#1487): Potency is the
## caster's `spell_damage`, and the Reach row always DESCRIBES the caster's
## `cast_range_hops` pipeline (the fold as text, via
## `Stat.resolve_with([]).describe()`). The per-cast facts — sections, affinity —
## live in the magic tray's configure view.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _MAGIC_SCENE := preload("res://ui/hud/combat_readout/combat_card_magic.tscn")
const _STUB_ARM := preload("res://test/fixtures/stub_arm.gd")


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
func _bound_card(stack: ArmedStack = null) -> Array:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity := _spawn_entity(graph)
	var reach: Stat = entity.stat_board.get_stat(&"cast_range_hops")
	reach.add_modifier(_mod(&"cast_range_hops", StatModifier.Operation.ADD_BASE, 3.0))
	reach.add_modifier(_mod(&"cast_range_hops", StatModifier.Operation.INCREASE, 50.0))
	var card: CombatCardMagic = _MAGIC_SCENE.instantiate()
	add_child_autofree(card)
	card._armed_stack = stack
	card.bind(entity)
	return [card, card.get_node("%ReachRow").get_node("%Value"), entity]


func test_no_spell_reach_row_describes_the_cast_range_pipeline() -> void:
	var pair := _bound_card()
	var value: Label = pair[1]
	assert_eq(value.text, "(X+3) × 1.5", "no spell: the row describes the fold, not a zero")




func test_potency_row_shows_the_casters_spell_damage() -> void:
	var pair := _bound_card()
	var card: CombatCardMagic = pair[0]
	var entity: Entity = pair[2]
	var stat: Stat = entity.stat_board.get_stat(&"spell_damage")
	stat.add_modifier(_mod(&"spell_damage", StatModifier.Operation.ADD_BASE, 37.0))
	assert_ne(float(stat.value), 0.0, "guard: the caster has spell damage")
	var value := card.get_node("%PotencyRow").get_node("%Value") as Label
	assert_eq(value.text, "%d" % int(stat.value), "potency is the caster's spell_damage")


## Selecting a spell is the configure view's business; the card's Reach row
## stays the caster's describe tier.
func test_selecting_a_spell_leaves_the_reach_row_on_the_describe_tier() -> void:
	var plan := MagicAttackPlan.new()
	var stack: ArmedStack = autofree(_STUB_ARM.stack_holding(plan))
	var pair := _bound_card(stack)
	var value: Label = pair[1]
	plan.attacker = pair[2]
	var before := value.text
	stack.selected_spell = _spell_with_hops(3)
	assert_eq(value.text, before, "a 3-hop spell does not move the card's reach")
	stack.selected_spell = null
	assert_eq(value.text, before, "nor does deselecting it")


## The cast's affinity lives in the configure view's AffinityLine (#1486).
func test_the_card_carries_no_affinity_row() -> void:
	var pair := _bound_card()
	var card: CombatCardMagic = pair[0]
	assert_null(card.find_child("AffinityRow", true, false), "the affinity line moved to the tray")
