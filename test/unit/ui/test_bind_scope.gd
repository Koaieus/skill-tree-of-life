extends GutTest

## [BindScope] — the one bookkeeping implementation behind every HUD binder's
## "let go of the previous hero before taking the next one" (#459).
##
## The load-bearing case is the lambda: `Callable.get_object()` on a GDScript
## lambda returns the *script*, not the node that made it, so a scope that did
## not store the exact Callable it connected could not release one.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _fresh_pool() -> PoolStat:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	return board.health


func test_release_disconnects_a_named_method() -> void:
	var pool := _fresh_pool()
	var scope := BindScope.new()
	scope.link(pool.value_changed, _noop)
	assert_true(pool.value_changed.is_connected(_noop))

	scope.release()
	assert_false(pool.value_changed.is_connected(_noop))
	assert_eq(scope.size(), 0)


func test_release_disconnects_an_anonymous_lambda() -> void:
	var pool := _fresh_pool()
	var scope := BindScope.new()
	var hits := [0]
	scope.link(pool.value_changed, func(): hits[0] += 1)

	pool.value_changed.emit()
	assert_eq(hits[0], 1, "sanity: the lambda is actually connected")

	scope.release()
	pool.value_changed.emit()
	assert_eq(hits[0], 1, "released — the lambda must not fire again")


func test_release_disconnects_an_unbound_callable() -> void:
	# `foo.unbind(1)` mints a NEW Callable per call, so `disconnect(foo.unbind(1))`
	# would not match the one that was connected. Storing the exact instance is
	# what makes these releasable — this is the assert that pins that.
	var pool := _fresh_pool()
	var scope := BindScope.new()
	var hits := [0]
	var bump := func(): hits[0] += 1
	scope.link(pool.current_changed, bump.unbind(1))

	pool.current_changed.emit(0)
	assert_eq(hits[0], 1, "sanity: the unbound callable is connected")

	scope.release()
	pool.current_changed.emit(0)
	assert_eq(hits[0], 1, "released — an `unbind`ed Callable must come off too")
	assert_true(pool.current_changed.get_connections().is_empty())


func test_release_is_idempotent_and_reusable() -> void:
	var pool := _fresh_pool()
	var scope := BindScope.new()
	scope.link(pool.value_changed, _noop)
	scope.release()
	scope.release()  # must not error on an already-empty scope

	scope.link(pool.value_changed, _noop)
	assert_eq(scope.size(), 1, "a released scope is reusable for the next bind")
	scope.release()


func test_release_survives_a_freed_emitter() -> void:
	# A hero dying mid-handover: the Signal still holds a dangling object
	# pointer, so the validity check has to come before `is_connected`.
	var node := Node.new()
	var scope := BindScope.new()
	scope.link(node.renamed, _noop)
	node.free()

	scope.release()
	assert_eq(scope.size(), 0, "released cleanly despite the emitter being gone")


func _noop() -> void:
	pass
