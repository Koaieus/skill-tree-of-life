class_name RingSystem
extends Node
## Owns the inner ring's rules. On ready it instances [member ring_scene] as a
## child (adjacency and addon grants exist only in-tree), samples it once into
## a [RingTable], and frees it at once — no live hidden Graph over the board.
## The only reader of the ring scene for rules; a display instances it again.

## The authored ring. Per-CoreClass rings are a later export. Tentative.
@export var ring_scene: PackedScene = preload("res://entity/ring/aspect_ring.tscn")

var _table: RingTable


func _ready() -> void:
	_sample()


func table() -> RingTable:
	if _table == null:
		_sample()
	return _table


func _sample() -> void:
	if ring_scene == null:
		return
	var inst := ring_scene.instantiate() as Graph
	if inst == null:
		push_error("RingSystem: ring_scene's root is not a Graph")
		return
	add_child(inst)
	_table = RingTable.sample(inst)
	remove_child(inst)
	inst.free()
