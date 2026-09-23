extends GutTest

## #1075 acceptance 4: the slot allocator on `GimbalBatch` only — acquire,
## release, reuse, `instance_count` growth. The shader is visual: measured on
## the gimbal-stage bench, never asserted here.

const _BATCH_SCENE := preload("res://skill_node/visuals/gimbal_mesh2d/gimbal_batch.tscn")

var _batch: GimbalBatch
var _owners: Array[Node] = []


func before_each() -> void:
	_batch = _BATCH_SCENE.instantiate()
	add_child_autofree(_batch)
	_owners = []
	for i in 12:
		var o := Node.new()
		o.name = "Owner%d" % i
		add_child_autofree(o)
		_owners.append(o)


func test_acquire_hands_out_distinct_slots_and_counts_them() -> void:
	var a := _batch.acquire(_owners[0])
	var b := _batch.acquire(_owners[1])
	assert_eq(a, 0, "first slot is 0")
	assert_eq(b, 1, "second slot is 1")
	assert_eq(_batch.slot_of(_owners[1]), 1)
	assert_eq(_batch.live_count(), 2)
	assert_eq(_batch.acquire(_owners[0]), a, "re-acquire is idempotent")
	assert_eq(_batch.live_count(), 2)


func test_release_then_acquire_reuses_the_freed_slot() -> void:
	_batch.acquire(_owners[0])
	var b := _batch.acquire(_owners[1])
	_batch.acquire(_owners[2])
	_batch.release(_owners[1])
	assert_eq(_batch.slot_of(_owners[1]), -1, "released owner has no slot")
	assert_eq(_batch.live_count(), 2)
	assert_eq(_batch.acquire(_owners[3]), b, "freed slot is handed out again")
	assert_eq(_batch.live_count(), 3)


func test_instance_count_grows_by_doubling_and_never_shrinks() -> void:
	assert_eq(_batch.capacity(), 0, "empty batch allocates nothing")
	_batch.acquire(_owners[0])
	assert_eq(_batch.capacity(), 8, "first grow is the minimum block")
	for i in range(1, 9):
		_batch.acquire(_owners[i])
	assert_eq(_batch.capacity(), 16, "9th slot doubles the buffer")
	assert_eq(_batch.live_count(), 9)
	for o in _owners:
		_batch.release(o)
	assert_eq(_batch.live_count(), 0)
	assert_eq(_batch.capacity(), 16, "capacity never shrinks")
	var mm: MultiMesh = _batch.get_node("Back").multimesh
	assert_eq(mm.instance_count, 16, "capacity IS MultiMesh.instance_count")
	assert_same(mm, _batch.get_node("Front").multimesh, "front and back share ONE MultiMesh")
