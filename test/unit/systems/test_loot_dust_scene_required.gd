extends GutTest

## `LootSystem.skill_dust_scene` is required — there is no code-built
## fallback addon. Unset: `_drop_skill_dust` logs an error and skips
## the drop entirely — no addon lands on the former core. Set: every minted
## dust is a real scene instance, so it carries a `scene_file_path`.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _DUST_SCENE := preload("res://skill_node/addons/defs/skill_dust_addon.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph
var _loot: LootSystem
var _victim: Entity
var _core: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_loot = LootSystem.new()
	add_child_autofree(_loot)

	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_core)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED  # non-empty candidate pool to draw from
	_graph.add_child(_victim)
	await get_tree().process_frame
	_victim.core_location = _core


func test_unset_scene_drops_no_dust_and_logs_an_error() -> void:
	_loot.skill_dust_scene = null

	_loot._drop_skill_dust(_victim)

	assert_true(_core.get_addons().is_empty(), "no scene configured -> no relic addon attached")
	assert_push_error("LootSystem.skill_dust_scene is unset; skipping dust drop")


func test_set_scene_mints_a_real_scene_instance() -> void:
	_loot.skill_dust_scene = _DUST_SCENE

	_loot._drop_skill_dust(_victim)

	var addons := _core.get_addons()
	assert_eq(addons.size(), 1, "dust addon attached once the scene is configured")
	for a in addons:
		assert_ne(a.scene_file_path, "", "minted dust is a scene instance, not a bare .new()")
