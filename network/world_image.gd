class_name WorldImage
extends RefCounted


static func capture(_graph: Graph) -> WorldImage:
	return WorldImage.new()


func apply(_graph: Graph, _entity_spawner: Callable, _turn_manager: TurnManager) -> void:
	pass


func to_bytes() -> PackedByteArray:
	return PackedByteArray()


static func from_bytes(_bytes: PackedByteArray) -> WorldImage:
	return null
