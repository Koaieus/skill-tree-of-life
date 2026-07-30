extends GutTest
## End-to-end: SkillNode._sync_visuals() resolves get_emblem_contributions()
## and pushes the winner into InnerDisk.set_carve() (docs/domain/skillnode-emblem.md).
## Exercises the real production wiring, not just the pure resolver.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")

var _graph: Graph
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)


func _disk() -> Node:
	return _node.get_node("Visuals/NodeVisualsComposite/ShaderStack/InnerDisk")


func test_default_node_with_no_archetype_renders_empty_dome() -> void:
	var disk := _disk()
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.NONE, "no archetype stamped -> the honest empty dome")


func test_default_node_carves_its_archetype_shape() -> void:
	_node.archetype = load("res://archetypes/strength.tres")
	_node._sync_visuals()
	var disk := _disk()
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.POLYGON, "no higher-priority carve -> archetype fallback wins")
	assert_eq(disk.weld_sides, 3, "STR carves a triangle")


func test_keystone_outranks_archetype_and_renders_empty_dome() -> void:
	_node.keystone = Keystone.new()
	_node._sync_visuals()
	var disk := _disk()
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.NONE, "keystone wins the carve, but has no dedicated renderer yet -> empty dome")


func test_skill_dust_addon_carves_the_loot_gem() -> void:
	var anchor := _node.get_node("Visuals/AddonAnchor")
	var dust := SkillDustAddon.new()
	anchor.add_child(dust)
	await get_tree().process_frame
	_node._sync_visuals()
	var disk := _disk()
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.GEM, "SkillDustAddon.get_emblem() -> LOOT carve -> gem dent")
	dust.queue_free()
