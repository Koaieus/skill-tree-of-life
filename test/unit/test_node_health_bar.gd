extends GutTest

## Per-node combat [HealthBar] visibility (skill_node/health_bar.gd). The bar
## hides via a `modulate.a` fade, not `visible` — so its show/hide correctness
## is entirely in the fade tween's bookkeeping.
##
## Regression for #147: force-deallocating a node (islanding cascade / death)
## synchronously resets its combat HP to 0 (`_reset_combat_health`), which fires
## `current_changed` and starts a fade-IN — while the bar's own `owner_changed`
## handler is CONNECT_DEFERRED and rebinds to null a frame later. The old
## `_fade_to` guard compared the *momentary* alpha (still 0.0 that frame) to its
## target and early-returned, orphaning the fade-in tween, which then drove the
## empty bar to full opacity and left it stuck until a hover re-triggered a fade.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _bar: ProgressBar


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	await get_tree().process_frame
	_bar = _node.get_node("Visuals/HealthBar")


## An allocated, undamaged node's bar is hidden (nothing to show).
func test_full_hp_bar_starts_hidden() -> void:
	assert_almost_eq(_bar.modulate.a, 0.0, 0.01, "an undamaged node shows no HP bar")


## The #147 case: deallocating a FULL-HP node must not leave an empty bar stuck
## on-screen. Deallocation zeroes combat HP synchronously, but the bar must end
## faded out once the owner rebinds to null.
func test_full_hp_dealloc_hides_the_bar() -> void:
	_alloc.force_deallocate(_node)
	await get_tree().process_frame  # flush deferred owner_changed → rebind to null
	await get_tree().process_frame
	await wait_seconds(0.6)         # let the fade settle
	assert_almost_eq(_bar.modulate.a, 0.0, 0.05,
			"a deallocated node must not leave a stuck empty HP bar (#147)")
