extends GutTest

## [method StatBoard.clone_live]'s contract: a clone is a board you may go on to
## MUTATE, not merely read.
##
## The regression these pin (found 2026-08-21, while sizing #498 step 3): the
## clone carried every stat's bin tally but not the `_modifiers` list it was
## folded from, and [method Stat._resync_bins_if_trivial] wipes the bins
## whenever that list holds 0 or 1 entries. So the FIRST modifier added to a
## clone threw the whole copied tally away — a board reading 40 STR came back
## 20 after a +10, with no error on any path. Removal was symmetric.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _live_board() -> StatBoard:
	var b: StatBoard = _BOARD.duplicate(true)
	b.apply_intrinsics()
	return b


func _add_base(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func test_clone_reads_the_same_as_its_source() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var dst := src.clone_live()
	assert_eq(dst.get_stat(&"strength").get_value(), src.get_stat(&"strength").get_value(),
		"a fresh clone reads exactly what its source reads")


func test_adding_a_modifier_to_a_clone_adds_to_the_copied_tally() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var before := float(src.get_stat(&"strength").get_value())

	var dst := src.clone_live()
	dst.add_modifier(_add_base(&"strength", 10.0))

	assert_eq(float(dst.get_stat(&"strength").get_value()), before + 10.0,
		"the clone's +10 must land ON TOP of the copied tally, not replace it")
	assert_eq(float(src.get_stat(&"strength").get_value()), before,
		"and it must not touch the source board")


func test_removing_a_modifier_from_a_clone_subtracts_from_the_copied_tally() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 10.0)
	src.add_modifier(shared)
	src.add_modifier(_add_base(&"strength", 10.0))
	var before := float(src.get_stat(&"strength").get_value())

	var dst := src.clone_live()
	# Removal is by identity, and the clone shares the source's instances (#377)
	# — so the handle a caller already holds is the handle that works.
	dst.remove_modifier(shared)

	assert_eq(float(dst.get_stat(&"strength").get_value()), before - 10.0,
		"the clone's removal must subtract exactly that modifier's contribution")
	assert_eq(float(src.get_stat(&"strength").get_value()), before,
		"and it must not touch the source board")


func test_a_clones_modifier_list_is_its_own_array() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 10.0)
	src.add_modifier(shared)
	var dst := src.clone_live()
	dst.remove_modifier(shared)
	assert_true(src.get_stat(&"strength").has_modifier(shared),
		"erasing from the clone's list must not erase from the source's")
	assert_false(dst.get_stat(&"strength").has_modifier(shared))


func test_a_clone_of_a_clone_still_carries_the_tally() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var expected := float(src.get_stat(&"strength").get_value())
	var twice := src.clone_live().clone_live()
	twice.add_modifier(_add_base(&"strength", 10.0))
	assert_eq(float(twice.get_stat(&"strength").get_value()), expected + 10.0,
		"a shadow snapshotted from a shadow is the AI-rollout case; it must not decay")


## A clone must also REACT (#506) — moving a source stat has to move every stat
## derived from it through the formula chain, the way it does on the live board.
##
## The pin is deliberately a CROSS-STAT chain and not a modifier on the target:
## `node_health = 10 + node_health_scaling x constitution` is a board intrinsic,
## so nothing here touches `node_health` directly. #498 step 2's max-HP test
## targeted `node_health` itself, which proved the cap was derived rather than
## snapshotted but said nothing about whether the chain survived the clone. It
## did not.


func _linear(source_id: StringName) -> StatFormula:
	var f := LinearFormula.new()
	f.source_stat_id = source_id
	return f


func test_a_clone_reacts_to_a_cross_stat_formula_chain() -> void:
	var src := _live_board()
	var dst := src.clone_live()
	var before := float(dst.get_stat(&"node_health").get_value())
	var rate := float(dst.get_stat(&"node_health_scaling").get_value())

	dst.add_modifier(_add_base(&"constitution", 10.0))

	assert_almost_eq(float(dst.get_stat(&"node_health").get_value()),
		before + 10.0 * rate, 0.001,
		"buffing CON on a shadow must move node_health through the intrinsic formula")


func test_a_clones_con_buff_never_reaches_the_source_board() -> void:
	var src := _live_board()
	var dst := src.clone_live()
	var src_before := float(src.get_stat(&"node_health").get_value())
	watch_signals(src.get_stat(&"node_health"))

	dst.add_modifier(_add_base(&"constitution", 10.0))

	assert_eq(float(src.get_stat(&"node_health").get_value()), src_before,
		"a simulated buff must not move the real board's derived stat")
	assert_signal_not_emitted(src.get_stat(&"node_health"), "value_changed",
		"and must not even NOTIFY it — a shadow firing recomputes on the live "
		+ "board is the failure that ruled out binding the shared modifiers")


func test_the_live_board_still_reacts_after_a_clone_is_taken() -> void:
	var src := _live_board()
	var before := float(src.get_stat(&"node_health").get_value())
	var rate := float(src.get_stat(&"node_health_scaling").get_value())
	src.clone_live()

	src.add_modifier(_add_base(&"constitution", 10.0))

	assert_almost_eq(float(src.get_stat(&"node_health").get_value()),
		before + 10.0 * rate, 0.001,
		"taking a shadow must not disturb the live board's own binding")


func test_a_clone_of_a_clone_reacts_too() -> void:
	var src := _live_board()
	var twice := src.clone_live().clone_live()
	var before := float(twice.get_stat(&"node_health").get_value())
	var rate := float(twice.get_stat(&"node_health_scaling").get_value())

	twice.add_modifier(_add_base(&"constitution", 10.0))

	assert_almost_eq(float(twice.get_stat(&"node_health").get_value()),
		before + 10.0 * rate, 0.001,
		"reactivity must survive a chain of snapshots, not just the first")


func test_a_formula_modifier_added_to_a_clone_reacts_on_the_clone_only() -> void:
	var src := _live_board()
	var dst := src.clone_live()
	var m := _add_base(&"strength", 1.0)
	m.formula = _linear(&"constitution")
	dst.add_modifier(m)
	watch_signals(src.get_stat(&"strength"))

	var str_before := float(dst.get_stat(&"strength").get_value())
	dst.add_modifier(_add_base(&"constitution", 4.0))

	assert_almost_eq(float(dst.get_stat(&"strength").get_value()), str_before + 4.0, 0.001,
		"a formula modifier granted DURING a simulation must react on the shadow")
	assert_signal_not_emitted(src.get_stat(&"strength"), "value_changed",
		"and must be localized on the way in, so it cannot bleed onto the source")


func test_a_formula_modifier_is_revoked_from_a_clone_by_its_LIVE_handle() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 1.0)
	shared.formula = _linear(&"constitution")
	src.add_modifier(_add_base(&"constitution", 10.0))
	src.add_modifier(shared)
	var src_before := float(src.get_stat(&"strength").get_value())

	var dst := src.clone_live()
	# The clone applies a PRIVATE copy of a formula-bearing modifier, but removal
	# is by identity and a caller (an AuraEffect revoke replayed against a
	# simulation) only holds the live instance. The board maps one to the other.
	dst.remove_modifier(shared)

	assert_almost_eq(float(dst.get_stat(&"strength").get_value()), src_before - 10.0, 0.001,
		"revoking by the live handle must drop the shadow's copy of that modifier")
	assert_eq(float(src.get_stat(&"strength").get_value()), src_before,
		"and must not touch the source board")


func test_a_revoked_formula_modifier_stops_reacting_on_the_clone() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 1.0)
	shared.formula = _linear(&"constitution")
	src.add_modifier(shared)
	var dst := src.clone_live()
	dst.remove_modifier(shared)

	var after_revoke := float(dst.get_stat(&"strength").get_value())
	dst.add_modifier(_add_base(&"constitution", 10.0))

	assert_eq(float(dst.get_stat(&"strength").get_value()), after_revoke,
		"a revoked modifier must be UNBOUND too, not merely subtracted — "
		+ "#498 step 3's cascade revokes mid-simulation and then reads on")


## A dropped clone is a reference CYCLE and is never collected without an
## explicit teardown (#514) — every Stat backpoints at the board holding it, and
## GDScript's RefCounted has no cycle collector. Measured 2026-08-21 before the
## fix: 122 objects leaked per clone_live() of `default_entity_board`, forever.


func _leak_per_clone(release: bool) -> float:
	var src := _live_board()
	for i in 20:  # warm up: first-call caches, StatDef loads, etc.
		var w := src.clone_live()
		if release:
			w.release()
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 200:
		var c := src.clone_live()
		if release:
			c.release()
		c = null
	var after := Performance.get_monitor(Performance.OBJECT_COUNT)
	return (after - before) / 200.0


func test_a_released_clone_is_collected() -> void:
	assert_almost_eq(_leak_per_clone(true), 0.0, 0.5,
		"clone_live() + release() must leave nothing behind — an AI rollout "
		+ "drops hundreds of boards per turn")


func test_an_unreleased_clone_is_the_thing_release_exists_for() -> void:
	# Guards the pin above from passing vacuously: if a future change made
	# clones collectable on their own, release() would be dead code and this
	# test says so out loud rather than leaving a no-op call in free_shadow().
	assert_gt(_leak_per_clone(false), 10.0,
		"an UNreleased clone must still leak — otherwise release() is dead code")


func test_release_refuses_a_live_board() -> void:
	var live := _live_board()
	var before := float(live.get_stat(&"node_health").get_value())
	var rate := float(live.get_stat(&"node_health_scaling").get_value())

	live.release()  # push_warning + no-op; an Entity's board is freed with the Entity
	live.add_modifier(_add_base(&"constitution", 10.0))

	assert_almost_eq(float(live.get_stat(&"node_health").get_value()),
		before + 10.0 * rate, 0.001,
		"release() on a live board must be refused outright — unwiring one would "
		+ "silently break batching, composed reads and every formula chain on it")


func test_a_released_clone_stops_reacting() -> void:
	var src := _live_board()
	var dst := src.clone_live()
	dst.release()
	var frozen := float(dst.get_stat(&"node_health").get_value())
	dst.get_stat(&"constitution").base_value += 10.0
	assert_eq(float(dst.get_stat(&"node_health").get_value()), frozen,
		"a released board is inert, not merely collectable — nothing may still "
		+ "be wired to fire recomputes on it")
