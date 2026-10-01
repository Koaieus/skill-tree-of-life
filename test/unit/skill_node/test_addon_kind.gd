extends GutTest

## An addon's kind is its scene, not its script: `toxin_addon.tscn` and the
## fixture `second_dot_addon.tscn` both run `dot_addon.gd`, yet they are two
## kinds — for uniqueness on a carrier and for the melee tray's outline colour.

const _TOXIN_SCENE := preload("res://skill_node/addons/defs/toxin_addon.tscn")
const _SECOND_DOT_SCENE := preload("res://test/fixtures/addons/second_dot_addon.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

var _graph: Graph
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "Carrier"
	_graph.add_skill_node(_node)
	_node.stake_level = 3
	_node.owned_by = _entity
	_node.allocation_level = 3
	await get_tree().process_frame


func _attach(scene: PackedScene, unique: bool = false) -> SkillNodeAddon:
	var a := scene.instantiate() as SkillNodeAddon
	if unique:
		a.unique = true
	_node.add_child(a)
	return a


# --- 1. two scenes on one script are two kinds --------------------------------

func test_scenes_sharing_a_script_have_distinct_kinds() -> void:
	var toxin: SkillNodeAddon = autofree(_TOXIN_SCENE.instantiate())
	var second: SkillNodeAddon = autofree(_SECOND_DOT_SCENE.instantiate())
	assert_eq(toxin.get_script(), second.get_script(), "fixture check: one shared script")
	assert_eq(toxin.get_kind(), _TOXIN_SCENE.resource_path)
	assert_eq(second.get_kind(), _SECOND_DOT_SCENE.resource_path)
	assert_ne(toxin.get_kind(), second.get_kind())


# --- 2. uniqueness is per scene ----------------------------------------------

func test_one_of_each_unique_kind_attaches_to_one_node() -> void:
	var toxin := _attach(_TOXIN_SCENE, true)
	var second := _attach(_SECOND_DOT_SCENE)
	assert_true(second.unique, "fixture check: the second DoT is authored unique")
	await get_tree().process_frame
	assert_true(_node.get_addons().has(toxin), "the unique toxin attaches")
	assert_true(_node.get_addons().has(second),
			"a unique addon of another scene on the same script attaches too")


# --- 3. a second of the same unique scene is refused --------------------------

func test_attach_refuses_a_second_instance_of_one_unique_scene() -> void:
	var first := _attach(_SECOND_DOT_SCENE)
	_attach(_SECOND_DOT_SCENE)
	await get_tree().process_frame
	assert_eq(_node.get_addons(), [first] as Array[SkillNodeAddon],
			"only the first unique instance stays on the carrier")
	assert_push_error("Duplicate unique addon")


func test_can_attach_refuses_only_the_same_unique_scene() -> void:
	_attach(_SECOND_DOT_SCENE)
	await get_tree().process_frame
	assert_false(_node.can_attach_addon(_SECOND_DOT_SCENE.resource_path),
			"a second instance of the carried unique scene is refused")
	assert_true(_node.can_attach_addon(_TOXIN_SCENE.resource_path),
			"another scene on the same script is a different kind")


# --- 5. the tray's outline colour follows the scene ---------------------------

func test_permanent_fixture_dot_gets_no_toxin_outline() -> void:
	_attach(_SECOND_DOT_SCENE)
	await get_tree().process_frame
	var battle: BattleSystem = autofree(BattleSystem.new())
	battle.temp_upgrade_catalog = _catalog
	battle.graph = _graph
	add_child(battle)
	var body := _MELEE_BODY.instantiate() as MeleeBody
	add_child_autofree(body)
	await get_tree().process_frame
	body.bind(_entity, battle, null)
	assert_eq(body._outline_colors_for(_node), [] as Array[Color],
			"a DoT addon that is not the toxin's scene earns no toxin outline")
