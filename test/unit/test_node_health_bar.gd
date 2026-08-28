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
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
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


# ── #660 acceptance 7: query + subscription WHILE SHOWN ─────────────────────
#
# The bar's live sources — the node pool's `current_changed`/`value_changed` and
# the owner's `node_health_cap_changed` — are scoped into a `SubBag` bound only
# while the bar is on screen. `Entity.node_health_cap_changed` has exactly one
# production listener in the repo (this bar), so its connection count IS the
# count of bound bars: the O(visible)-not-O(owned) claim is directly assertable.


func _hp() -> PoolStat:
	return _node.node_board.get_stat(&"node_health") as PoolStat


## Bound bars, entity-wide. See the block comment above for why this is exact.
func _bound_bars() -> int:
	return _entity.node_health_cap_changed.get_connections().size()


func _extra_node(nm: String) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.name = nm
	_graph.skill_nodes_container.add_child(n)
	return n


## Move the OWNER's `node_health` baseline — the thing whose fan-out #660
## deleted, and the sole source of [signal Entity.node_health_cap_changed].
## Goes through `_entity.stat_board`, not the board handed to it: [Entity]
## duplicates the resource on adopt, so writing the original is a no-op here.
func _boost_cap(amount: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"node_health"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = amount
	_entity.stat_board.add_modifier(m)


## An allocated, undamaged, unhovered node holds NO subscription to its owner —
## the whole point of #660. Nothing per-node happens when the owner's CON moves.
func test_undamaged_node_holds_no_subscription() -> void:
	assert_eq(_bound_bars(), 0, "an undamaged, unhovered node subscribes to nothing")


## …and that stays true as the owned count grows. Damage exactly one node out of
## nine; the listener count is 1, not 9. This is the O(visible) assertion.
func test_listener_count_tracks_visible_bars_not_owned_nodes() -> void:
	for i in range(8):
		_alloc.force_allocate(_entity, _extra_node("N%d" % (i + 1)))
	await get_tree().process_frame
	assert_eq(_bound_bars(), 0, "nine owned, none damaged -> zero listeners")

	_node.take_damage(3.0, null)
	assert_eq(_bound_bars(), 1, "nine owned, one damaged -> exactly one listener")


## Damage sprouts the binding; healing back to full releases it.
func test_damage_binds_and_heal_to_full_releases() -> void:
	_node.take_damage(3.0, null)
	assert_lt(float(_hp().current), _hp().value, "the hit must actually land")
	assert_eq(_bound_bars(), 1, "a damaged node's bar is bound")

	_node.heal_damage(999.0, null)
	assert_almost_eq(float(_hp().current), _hp().value, 0.001, "healed to full")
	assert_eq(_bound_bars(), 0, "heal-to-full releases the binding")


## Hover is the other reason a bar is on screen, and it binds the same way.
func test_hover_binds_and_unhover_releases() -> void:
	_node.mouse_entered.emit()
	assert_eq(_bound_bars(), 1, "a hovered bar is bound even at full HP")
	_node.mouse_exited.emit()
	assert_eq(_bound_bars(), 0, "unhover releases it again")


## A VISIBLE bar hears the entity-level cap move and repaints — both ends of it,
## since the pool stores damage taken and a cap move is therefore also a
## `current` move with no `current_changed` of its own.
func test_visible_bar_updates_on_an_entity_cap_move() -> void:
	_node.take_damage(3.0, null)
	var before_max: float = _bar.max_value
	assert_eq(_bound_bars(), 1)

	_boost_cap(30.0)
	assert_gt(_hp().value, before_max, "the entity baseline really moved")
	assert_almost_eq(_bar.max_value, _hp().value, 0.001,
			"a visible bar tracks the entity cap move")

	await wait_seconds(0.6)  # let the heal tween settle
	assert_almost_eq(_bar.value, float(_hp().current), 0.5,
			"and its fill follows the derived current")


## No visible pop on bind: the sprout paints from live state BEFORE the fade-in
## starts, so no frame ever shows the stale fill a released bar was left with.
## The strong form — a cap move the released bar could not have heard.
func test_first_paint_after_an_unheard_cap_move_is_not_stale() -> void:
	# Bind then release, so the bar carries a concrete, now-doomed fill.
	_node.mouse_entered.emit()
	_node.mouse_exited.emit()
	var stale_max: float = _bar.max_value

	_boost_cap(30.0)
	assert_eq(_bound_bars(), 0, "a released bar heard nothing")
	assert_almost_eq(_bar.max_value, stale_max, 0.001, "…and is now genuinely stale")

	_node.mouse_entered.emit()
	assert_almost_eq(_bar.max_value, _hp().value, 0.001, "first paint snaps the cap")
	assert_almost_eq(_bar.value, float(_hp().current), 0.001, "first paint snaps the fill")
	assert_almost_eq(_bar.modulate.a, 0.0, 0.001,
			"and it landed before the fade-in stepped: no frame renders the stale fill")


## The same, on the damage path, and with no frame awaited: the value is already
## correct in the same call stack that made the bar visible.
func test_first_paint_on_damage_snaps_rather_than_tweening_from_stale() -> void:
	_node.take_damage(3.0, null)
	assert_almost_eq(_bar.value, float(_hp().current), 0.001,
			"the sprout snapped to live HP rather than tweening down from a stale fill")
	assert_almost_eq(_bar.modulate.a, 0.0, 0.001, "fade-in has not stepped yet")


## Release is invisible too: `clear()` touches no drawing state, so the fade-out
## and the heal tween already in flight run to completion after the unbind.
func test_release_leaves_the_bar_settled_and_faded_out() -> void:
	_node.take_damage(3.0, null)
	await get_tree().process_frame
	_node.heal_damage(999.0, null)
	assert_eq(_bound_bars(), 0, "released on heal-to-full")

	await wait_seconds(0.7)
	assert_almost_eq(_bar.modulate.a, 0.0, 0.05, "faded out after release")
	assert_almost_eq(_bar.value, float(_hp().current), 0.5,
			"the in-flight heal tween still finished on the released bar")
