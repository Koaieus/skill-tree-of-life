extends GutTest

## [SubBag] (#9) — connect-on-show, clear-on-hide for ephemeral UI. The three
## scenarios named in the acceptance: double-show without a dismiss must not
## double-connect, a hidden-but-alive pooled panel that `clear()`s must see
## zero further callbacks, and `clear()` after the emitter has been freed must
## not error.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _fresh_pool() -> PoolStat:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	return board.health


func test_on_connects() -> void:
	var pool := _fresh_pool()
	var bag := SubBag.new()
	var hits := [0]
	bag.on(pool.value_changed, func(): hits[0] += 1)

	pool.value_changed.emit()
	assert_eq(hits[0], 1)


func test_on_twice_does_not_double_connect() -> void:
	# Double-show without an intervening dismiss: the same (sig, fn) pair
	# connected a second time must not fire twice per emit.
	var pool := _fresh_pool()
	var bag := SubBag.new()
	var hits := [0]
	var handler := func(): hits[0] += 1

	bag.on(pool.value_changed, handler)
	bag.on(pool.value_changed, handler)
	pool.value_changed.emit()

	assert_eq(hits[0], 1, "duplicate on() of the same pair must no-op")


func test_now_connects_and_invokes_immediately() -> void:
	var pool := _fresh_pool()
	var bag := SubBag.new()
	var hits := [0]

	bag.now(pool.value_changed, func(): hits[0] += 1)
	assert_eq(hits[0], 1, "now() must invoke synchronously on connect")

	pool.value_changed.emit()
	assert_eq(hits[0], 2, "now() must also leave the subscription live")


func test_pooled_panel_clear_on_hide_stops_all_callbacks() -> void:
	# The hidden-but-alive scenario: the panel is not freed, just hidden, and
	# must clear() rather than trust teardown — free-time auto-disconnect
	# never fires for it.
	var pool := _fresh_pool()
	var bag := SubBag.new()
	var hits := [0]
	bag.now(pool.value_changed, func(): hits[0] += 1)
	assert_eq(hits[0], 1, "sanity: now() fired once on connect")

	bag.clear()
	pool.value_changed.emit()
	pool.value_changed.emit()

	assert_eq(hits[0], 1, "cleared bag must see zero callbacks on later emits")


func test_clear_is_idempotent() -> void:
	var pool := _fresh_pool()
	var bag := SubBag.new()
	bag.on(pool.value_changed, _noop)

	bag.clear()
	bag.clear()  # must not error on an already-cleared bag

	assert_false(pool.value_changed.is_connected(_noop))


func test_clear_after_emitter_freed_does_not_error() -> void:
	var node := Node.new()
	var bag := SubBag.new()
	bag.on(node.renamed, _noop)
	node.free()

	bag.clear()  # must not error despite the dangling emitter reference
	assert_true(true, "reaching this line means clear() survived the free")


func test_clear_after_target_freed_does_not_error() -> void:
	var pool := _fresh_pool()
	var target := Node.new()
	var bag := SubBag.new()
	bag.on(pool.value_changed, target.queue_free)

	target.free()

	bag.clear()  # Godot already auto-disconnected the freed target; must not error
	assert_true(true, "reaching this line means clear() survived the free")


func _noop() -> void:
	pass
