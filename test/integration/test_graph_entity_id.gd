extends GutTest

## `Entity.entity_id` / `Graph.get_by_entity_id` — the entity half of the wire
## identity contract (#509). Same shape as `stable_id` (see
## test_graph_stable_id.gd), with one deliberate difference: entity ids are
## minted EAGERLY on entry to `entities_container`, so a command built in the
## same frame as a spawn already carries a real id.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _spawn() -> Entity:
	var e := _ENTITY_SCENE.instantiate() as Entity
	_graph.entities_container.add_child(e)
	return e


func test_spawned_entity_gets_a_nonzero_id() -> void:
	assert_ne(_spawn().entity_id, 0)


func test_two_entities_get_distinct_ids() -> void:
	var a := _spawn()
	var b := _spawn()

	assert_ne(a.entity_id, b.entity_id)


func test_get_by_entity_id_resolves_to_the_right_entity() -> void:
	var a := _spawn()
	var b := _spawn()

	assert_eq(_graph.get_by_entity_id(a.entity_id), a)
	assert_eq(_graph.get_by_entity_id(b.entity_id), b)


func test_zero_resolves_to_null() -> void:
	assert_null(_graph.get_by_entity_id(0), "0 means unminted, never an entity")


func test_unknown_id_returns_null() -> void:
	assert_null(_graph.get_by_entity_id(999999))


func test_a_removed_entity_no_longer_resolves() -> void:
	var a := _spawn()
	var a_id := a.entity_id
	_graph.entities_container.remove_child(a)
	a.free()

	assert_null(_graph.get_by_entity_id(a_id))


func test_a_removed_id_is_not_reused_by_the_next_entity() -> void:
	var a := _spawn()
	var a_id := a.entity_id
	_graph.entities_container.remove_child(a)
	a.free()

	var b := _spawn()

	assert_ne(b.entity_id, a_id)
	assert_eq(_graph.get_by_entity_id(b.entity_id), b)


func test_an_id_survives_a_sibling_removal() -> void:
	var a := _spawn()
	var b := _spawn()
	var b_id := b.entity_id
	_graph.entities_container.remove_child(a)
	a.free()

	assert_eq(_graph.get_by_entity_id(b_id), b)


## The scene-authored path: `dev_sandbox.tscn` parents its Player and Enemy
## under `$Entities` in the `.tscn`, so they enter the tree BEFORE Graph._ready
## connects `child_entered_tree`. Without the backfill sweep they would sit at
## id 0 forever and every command naming them would fail to resolve.
func test_entities_authored_into_the_scene_are_backfilled() -> void:
	var g: Graph = _GRAPH_SCENE.instantiate()
	var authored := _ENTITY_SCENE.instantiate() as Entity
	(g.get_node("Entities") as Node).add_child(authored)
	add_child_autofree(g)

	assert_ne(authored.entity_id, 0, "authored entity was minted")
	assert_eq(g.get_by_entity_id(authored.entity_id), authored)


func test_re_adding_an_entity_keeps_its_id() -> void:
	var a := _spawn()
	var a_id := a.entity_id
	_graph.entities_container.remove_child(a)
	_graph.entities_container.add_child(a)

	assert_eq(a.entity_id, a_id, "identity is minted once, not per parenting")
	assert_eq(_graph.get_by_entity_id(a_id), a)
