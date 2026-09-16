extends GutTest

## #913 — CombatValueRow becomes self-binding: it reads its own StatBoard stat
## and node-local override rather than the card pushing both in. Covers the
## issue's five acceptance points except #5 (mise run check / test:dir, which
## is a CI-shaped check, not a GUT assertion).

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BASE_CARD_SCENE := preload("res://ui/hud/combat_readout/combat_card.tscn")
const _ROW_SCENE := preload("res://ui/hud/combat_readout/combat_value_row.tscn")
const _DEFENSE_SCENE := preload("res://ui/hud/combat_readout/combat_card_defense.tscn")
const _MELEE_SCENE := preload("res://ui/hud/combat_readout/combat_card_melee.tscn")

## Every card/row script this fence owns — acceptance #4's grep target.
const _OWNED_SCRIPTS := [
	"res://ui/hud/combat_readout/combat_readout_card.gd",
	"res://ui/hud/combat_readout/combat_value_row.gd",
	"res://ui/hud/combat_readout/combat_card_defense.gd",
	"res://ui/hud/combat_readout/combat_card_melee.gd",
	"res://ui/hud/combat_readout/combat_card_ranged.gd",
	"res://ui/hud/combat_readout/combat_card_crit.gd",
	"res://ui/hud/combat_readout/combat_card_magic.gd",
]


func _spawn_entity(graph: Graph) -> Entity:
	var entity: Entity = _ENTITY_SCENE.instantiate()
	graph.entities_container.add_child(entity)
	return entity


func _spawn_owned_node(graph: Graph, owner: Entity) -> SkillNode:
	var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
	node.owned_by = owner
	graph.add_skill_node(node)
	return node


func _static_mod(id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


# --- Acceptance 1: a bare row, no subclass, self-binds and updates ---------

func test_bare_row_with_no_subclass_shows_board_value_and_updates_on_change() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity := _spawn_entity(graph)
	entity.stat_board.armor.base_value = 12.0

	# The base scene, un-subclassed — CombatReadoutCard is its own script.
	var card: CombatReadoutCard = _BASE_CARD_SCENE.instantiate()
	add_child_autofree(card)
	var row: CombatValueRow = _ROW_SCENE.instantiate()
	row.stat_id = &"armor"
	card.get_node("Padded/TitleAndBody/Body").add_child(row)

	card.bind(entity)
	assert_eq(row.get_node("%Value").text, "12", "row shows the board's armor baseline with no subclass code")

	entity.stat_board.armor.base_value = 20.0
	assert_eq(row.get_node("%Value").text, "20", "row updates on its own — it self-bound to armor.value_changed")


# --- Acceptance 2: hover override shows and clears --------------------------

func test_hover_node_override_shows_then_clears_on_unhover() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity := _spawn_entity(graph)
	var node := _spawn_owned_node(graph, entity)
	node.add_local_modifier(_static_mod(&"node_health", 15.0))

	var card: CombatCardDefense = _DEFENSE_SCENE.instantiate()
	add_child_autofree(card)
	card.bind(entity)

	var health_row: CombatValueRow = card.get_node("%NodeHealthRow")
	assert_eq(health_row.get_node("%Value").text, "10", "at rest the row shows the entity baseline")
	assert_false(health_row.get_node("%OverrideBadge").visible, "no badge before hover")

	card.set_hover_node(node)
	assert_eq(health_row.get_node("%Value").text, "25", "hovering an owned node with a local override shows it")
	assert_true(health_row.get_node("%OverrideBadge").visible, "override badge lights up on hover")

	card.set_hover_node(null)
	assert_eq(health_row.get_node("%Value").text, "10", "unhover reverts to the entity baseline")
	assert_false(health_row.get_node("%OverrideBadge").visible, "badge clears on unhover")


# --- Acceptance 3: the new rows exist, the melee sliver is gone -------------

func test_defense_card_has_node_health_and_spike_regen_rows() -> void:
	var card := _DEFENSE_SCENE.instantiate()
	add_child_autofree(card)
	var health_row: CombatValueRow = card.get_node("%NodeHealthRow")
	var regen_row: CombatValueRow = card.get_node("%SpikeRegenRow")
	assert_eq(health_row.stat_id, &"node_health")
	assert_eq(regen_row.stat_id, &"spike_regen")


func test_melee_card_has_blunting_row_and_no_sliver() -> void:
	var card := _MELEE_SCENE.instantiate()
	add_child_autofree(card)
	var blunting_row: CombatValueRow = card.get_node("%BluntingRow")
	assert_eq(blunting_row.stat_id, &"blunting")
	assert_null(card.find_child("SizeSliver", true, false), "the re-derived STR-breakpoint sliver is retired, not just hidden")


# --- Acceptance 4: no subclass reimplements the override lookup ------------

func test_no_owned_script_calls_local_override_or_null() -> void:
	for path in _OWNED_SCRIPTS:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("_local_override_or_null"),
			"%s should no longer reference the retired card-level override lookup" % path)
