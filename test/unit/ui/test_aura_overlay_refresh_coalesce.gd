extends GutTest

## [AuraOverlay] walks every SkillNode and every Edge per refresh, so an
## allocation-signal burst — a forced-dealloc cascade, a concede strip — must
## cost ONE walk per frame, not one per landing. Each landing still paints in
## its own frame: the coalesce is same-frame only, so the beat clock's
## one-landing-per-step cascade stays in step with the node paint.
## Cost at scale: `test/perf/bench_aura_refresh_cost.gd`.


const _NODE_COUNT := 6


## Counts walks without a production seam — every entry point dispatches
## through `_refresh`.
class _CountingAura extends AuraOverlay:
	var refreshes := 0

	func _refresh() -> void:
		refreshes += 1
		super()


var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _aura: _CountingAura


func before_each() -> void:
	var world := TestWorld.create(self)
	_graph = world.graph
	_nodes = []
	for i in _NODE_COUNT:
		_nodes.append(world.add_node(&"", Vector2(i * 200.0, 0.0)))
	for i in _NODE_COUNT - 1:
		world.link(_nodes[i], _nodes[i + 1])
	_alloc = world.allocator()
	_entity = world.add_entity("")
	await get_tree().process_frame
	for sn in _nodes:
		_alloc.force_allocate(_entity, sn)
	_entity.core_location = _nodes[0]

	_aura = _CountingAura.new()
	_aura.graph = _graph
	_aura.allocation_system = _alloc
	add_child_autofree(_aura)
	await get_tree().process_frame
	_aura.refreshes = 0


func test_a_synchronous_dealloc_burst_refreshes_once() -> void:
	_alloc.deallocate_all_owned(_entity)
	await get_tree().process_frame
	assert_eq(_aura.refreshes, 1,
		"%d force-deallocates in one frame must cost one graph walk" % _NODE_COUNT)


func test_landings_in_separate_frames_each_refresh() -> void:
	_alloc.force_deallocate(_nodes[_NODE_COUNT - 1])
	await get_tree().process_frame
	_alloc.force_deallocate(_nodes[_NODE_COUNT - 2])
	await get_tree().process_frame
	assert_eq(_aura.refreshes, 2, "one refresh per frame that saw a landing")


func test_entity_death_joins_the_same_frame_refresh() -> void:
	_alloc.force_deallocate(_nodes[_NODE_COUNT - 1])
	Events.entity_died.emit(_entity)
	await get_tree().process_frame
	assert_eq(_aura.refreshes, 1)
