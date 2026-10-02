class_name WorldImage
extends RefCounted
## A whole world as one typed value: the entity half and the graph half, each a
## snapshot codec's bytes. The ONE owner of capturing a world and of the order
## it is put back in — the wire ([WorldSyncChannel]'s resync) and the disk (a
## save) are only its transports, so state a future system needs carried goes
## into a codec and both transports pick it up.
##
## Transport-free on purpose: no link, no role, no join/repair flags — those
## are wire facts and stay on the channel. See docs/adr/0042-*.md.

## Bumped when [method to_bytes]'s envelope (not a codec's payload) changes shape.
const FORMAT_VERSION := 1

var entity_bytes: PackedByteArray
var graph_bytes: PackedByteArray


func _init(entities: PackedByteArray = PackedByteArray(),
		graph_half: PackedByteArray = PackedByteArray()) -> void:
	entity_bytes = entities
	graph_bytes = graph_half


## Both halves of [param graph]'s world. The turn cursor rides the entity half.
static func capture(graph: Graph) -> WorldImage:
	return WorldImage.new(EntitySnapshot.encode(graph), GraphSnapshot.encode(graph))


## True when there is no graph half to apply — `GraphSnapshot` reads a size
## header off the front, so an empty half is a decode error, never a no-op.
func is_empty() -> bool:
	return graph_bytes.is_empty()


## Puts this world onto [param graph], in dependency order: entities
## (spawn/remove), graph, the entities' graph refs, HP (a pool clamps to a cap
## the owner's now-whole board decides), then the turn cursor (its
## [signal TurnManager.turn_started] reaches the HUD, so it must not fire over a
## half-restored world). [param entity_spawner] materialises an entity the image
## names but [param graph] lacks; [param turn_manager] may be null.
func apply(graph: Graph, entity_spawner: Callable, turn_manager: TurnManager) -> void:
	if graph == null or is_empty():
		return
	EntitySnapshot.decode(entity_bytes, graph, entity_spawner)
	GraphSnapshot.decode(graph_bytes, graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, graph, entity_spawner)
	GraphSnapshot.restore_hp(graph_bytes, graph)
	EntitySnapshot.restore_turn_cursor(entity_bytes, graph, turn_manager)


## The disk form: both halves in one versioned envelope.
func to_bytes() -> PackedByteArray:
	return GraphSnapshot._pack({
		"v": FORMAT_VERSION, "entities": entity_bytes, "graph": graph_bytes,
	})


## Inverse of [method to_bytes]; null for bytes that are not an image of this
## format version.
static func from_bytes(bytes: PackedByteArray) -> WorldImage:
	if bytes.size() < 4:
		return null
	var payload := GraphSnapshot._unpack(bytes)
	if payload == null or int(payload.get("v", -1)) != FORMAT_VERSION:
		return null
	return WorldImage.new(
			payload.get("entities", PackedByteArray()), payload.get("graph", PackedByteArray()))
