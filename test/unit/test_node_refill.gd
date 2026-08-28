extends GutTest

## Node combat-HP depletion → refill round-trip (#137).
##
## The Spell Playground's Reset button is `SkillNode.refill()` over every node.
## The issue reported that a node killed by a cast stays dead through Reset —
## these tests pin the claim that `refill()` itself is sound (it is), which
## isolates the real cause to the in-flight-damage race in `_cast()`.
##
## Also covers HealthBar: it binds the pool the moment there is damage to show
## (#660 scoped that bind to while-shown), and a depleted node must read as an
## *empty* bar, not as no bar.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame  # _ready: node_board + hp binding

	# Ownership without an AllocationSystem — the playground authors it the same
	# way (scene-baked `owned_by`), and it's what seeds the combat-health pool.
	_node.owned_by = _entity
	await get_tree().process_frame


func _pool() -> PoolStat:
	return _node.node_board.get_stat(&"node_health") as PoolStat


func test_owned_node_starts_at_full_hp() -> void:
	var hp := _pool()
	assert_not_null(hp, "owning a node must seed its node_health pool")
	assert_gt(float(hp.value), 0.0, "max HP should come from the entity baseline")
	assert_eq(hp.current, float(hp.value), "a freshly owned node starts full")


func test_refill_restores_a_depleted_node() -> void:
	var hp := _pool()
	watch_signals(_node)

	_node.take_damage(float(hp.value) + 1000.0, null)
	assert_eq(hp.current, 0.0, "an overkill hit empties the pool")
	assert_signal_emitted(_node, "depleted", "hitting 0 HP emits `depleted`")

	_node.refill()
	assert_eq(hp.current, float(hp.value), "refill() brings a dead node back to full")


func test_refill_restores_a_node_killed_by_accumulated_chip_damage() -> void:
	# The multi-cast kill: no single hit is lethal, together they are. Without a
	# per-cast auto-refill this is the playground's whole point.
	var hp := _pool()
	var chip: float = float(hp.value) / 4.0
	for i in 5:
		_node.take_damage(chip, null)
	assert_eq(hp.current, 0.0, "accumulated chip damage kills")

	_node.refill()
	assert_eq(hp.current, float(hp.value), "refill() undoes accumulated damage too")


## #660 acceptance 7 re-point. This used to open by asserting the bar ALREADY
## mirrored the pool while sitting invisible at full HP — the always-bound
## contract, which is exactly what got scoped away: an undamaged, unhovered bar
## now holds no subscription and paints nothing, so `max_value`/`value` are
## deliberately whatever the scene baked. The two replacement asserts pin the
## property that actually matters, and every assert from the damage onward is
## unchanged and still passes: the sprout snaps to live state, so no frame ever
## renders the stale pair.
func test_health_bar_sprouts_on_damage_and_tracks_it() -> void:
	var bar: ProgressBar = _node.get_node("Visuals/HealthBar")
	await get_tree().process_frame  # HealthBar._on_owner_changed is deferred

	var hp := _pool()
	assert_almost_eq(bar.modulate.a, 0.0, 0.001, "an undamaged node shows no bar")
	assert_eq(_entity.node_health_cap_changed.get_connections().size(), 0,
			"…and its released bar holds no subscription to the owner's cap")

	_node.take_damage(float(hp.value) + 1000.0, null)
	assert_eq(bar.max_value, float(hp.value), "the sprout's first paint snaps the cap")
	assert_eq(hp.current, 0.0)
	# Both the fill and the fade-in are tweened — let them land before reading.
	await wait_seconds(0.3)
	assert_almost_eq(bar.value, 0.0, 0.001, "the bar drains to empty")
	assert_almost_eq(bar.modulate.a, 1.0, 0.001,
			"a depleted node shows an empty bar rather than hiding it")

	_node.refill()
	await wait_seconds(0.6)
	assert_almost_eq(bar.value, float(hp.value), 0.001, "Reset visibly refills the bar")
	assert_almost_eq(bar.modulate.a, 0.0, 0.001, "a full node hides its bar again")
