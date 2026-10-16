class_name TestWorld
extends RefCounted

static func create(_gut: GutTest) -> TestWorld:
	return TestWorld.new()

var test: GutTest
var graph: Graph

func add_node(_id: StringName, _pos: Variant = null) -> SkillNode:
	return null

func link(_a: SkillNode, _b: SkillNode) -> Edge:
	return null

func add_entity(_display_name: String, _board: EntityStatBoard = null,
		_faction: Faction = null, _color: Color = Color.WHITE) -> Entity:
	return null

func allocator() -> AllocationSystem:
	return null

func allocate(_entity: Entity, _nodes: Array) -> void:
	pass
