extends GutTest

## [method StatBoard.begin_batch] / [method StatBoard.end_batch] — coalescing a
## burst of modifier installs into ONE `value_changed` per stat that moved.
##
## Why this exists (measured 2026-08-17, 2000-node level at 200 owned): a
## procgen node granting both `constitution` and `node_health` moved the
## entity's `node_health` twice for one allocation, and each move re-synced the
## combat health pool of EVERY owned node — 396 syncs for 197 nodes, 75-83% of
## the whole allocation's cost. Batching made it 198. The ordering test below is
## the load-bearing one: an unordered flush emits the dependent stat, then the
## source re-dirties it, and the second cascade comes straight back.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _board() -> EntityStatBoard:
	var b: EntityStatBoard = _BOARD.duplicate(true)
	b.apply_intrinsics()
	return b


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


## Counts into an Array, not a captured int — see `.claude/rules/testing.md`.
func _count_emissions(s: Stat) -> Array:
	var seen: Array = []
	s.value_changed.connect(func() -> void: seen.append(1))
	return seen


func test_two_modifiers_on_one_stat_emit_once() -> void:
	var b := _board()
	var seen := _count_emissions(b.get_stat(&"strength"))
	b.begin_batch()
	b.add_modifier(_mod(&"strength", 5.0))
	b.add_modifier(_mod(&"strength", 7.0))
	assert_eq(seen.size(), 0, "nothing may notify while the batch is open")
	b.end_batch()
	assert_eq(seen.size(), 1, "two installs on one stat must settle into one notification")


func test_value_is_correct_mid_batch() -> void:
	var b := _board()
	var before := float(b.get_value(&"strength"))
	b.begin_batch()
	b.add_modifier(_mod(&"strength", 5.0))
	# Deferring the SIGNAL must never defer the VALUE — get_value recomputes
	# from the bins, so a read taken mid-batch is already correct.
	assert_almost_eq(float(b.get_value(&"strength")), before + 5.0, 0.001,
		"a read inside a batch must see the installed modifier")
	b.end_batch()
	assert_almost_eq(float(b.get_value(&"strength")), before + 5.0, 0.001)


## The one that matters. `node_health` derives from `constitution` via a board
## intrinsic, so touching BOTH in one batch means the flush must emit
## `constitution` first — otherwise `node_health` emits, the constitution
## cascade re-dirties it, and it emits again.
func test_a_stat_and_its_formula_source_in_one_batch_emit_the_dependent_once() -> void:
	var b := _board()
	var seen := _count_emissions(b.get_stat(&"node_health"))
	b.begin_batch()
	# ORDER IS THE POINT: the dependent is dirtied FIRST, so the dirty set's
	# natural (insertion) order is the wrong one. Without the depth sort this
	# emits node_health, then constitution's cascade re-dirties it, and it
	# emits a second time. Verified by disabling the sort — this assert is the
	# only one in the file that goes red when you do.
	b.add_modifier(_mod(&"node_health", 2.0))
	b.add_modifier(_mod(&"constitution", 3.0))
	b.end_batch()
	assert_eq(seen.size(), 1,
		"node_health must notify once even though both it and its source moved")


func test_the_dependent_still_lands_on_the_right_value() -> void:
	var b := _board()
	var before := float(b.get_value(&"node_health"))
	var con_scale := float(b.get_value(&"node_health_scaling"))
	b.begin_batch()
	b.add_modifier(_mod(&"node_health", 2.0))
	b.add_modifier(_mod(&"constitution", 3.0))
	b.end_batch()
	# Coalescing notifications must not coalesce arithmetic: both contributions
	# are present, the CON one scaled by node_health_scaling per the intrinsic.
	assert_almost_eq(float(b.get_value(&"node_health")), before + 2.0 + 3.0 * con_scale, 0.001,
		"batching must change when listeners hear, never what the value is")


func test_unbatched_behaviour_is_unchanged() -> void:
	var b := _board()
	var seen := _count_emissions(b.get_stat(&"strength"))
	b.add_modifier(_mod(&"strength", 5.0))
	b.add_modifier(_mod(&"strength", 7.0))
	assert_eq(seen.size(), 2, "outside a batch every install still notifies immediately")


func test_nested_batches_flush_once_at_the_outermost_end() -> void:
	var b := _board()
	var seen := _count_emissions(b.get_stat(&"strength"))
	b.begin_batch()
	b.begin_batch()
	b.add_modifier(_mod(&"strength", 5.0))
	b.end_batch()
	assert_eq(seen.size(), 0, "an inner end_batch must not flush")
	assert_true(b.is_batching(), "and must leave the outer batch open")
	b.end_batch()
	assert_eq(seen.size(), 1)
	assert_false(b.is_batching())


func test_removal_is_batched_too() -> void:
	var b := _board()
	var m1 := _mod(&"strength", 5.0)
	var m2 := _mod(&"strength", 7.0)
	b.add_modifier(m1)
	b.add_modifier(m2)
	var seen := _count_emissions(b.get_stat(&"strength"))
	b.begin_batch()
	b.remove_modifier(m1)
	b.remove_modifier(m2)
	b.end_batch()
	assert_eq(seen.size(), 1, "a batched dealloc must settle into one notification too")


func test_unmatched_end_batch_warns_and_leaves_the_board_usable() -> void:
	var b := _board()
	# The guard exists because an unmatched begin_batch would silently swallow
	# every later notification on this board; the mirror case must not corrupt
	# the depth into negative territory.
	b.end_batch()
	assert_false(b.is_batching())
	var seen := _count_emissions(b.get_stat(&"strength"))
	b.add_modifier(_mod(&"strength", 5.0))
	assert_eq(seen.size(), 1, "the board still notifies normally after a stray end_batch")


# --- Pool stats inside a batch ----------------------------------------------
#
# PoolStat and its subclasses route their emissions through the same helper, so
# a pool modifier installed inside a batch has its notification deferred too.
# That is intended (one notification per settle), but the failure mode if it
# were wrong is a gauge that silently stops updating — SP/DP/MP and the health
# pool all bind these signals from the HUD. These pin that nothing is LOST and
# that the ratchet still runs on the add path rather than off the signal.


func test_a_pool_cap_modifier_in_a_batch_still_notifies_and_still_ratchets() -> void:
	var b := _board()
	var health := b.get_stat(&"health") as PoolStat
	health.restore_to_full()
	var before_max := float(health.get_value())
	var before_current := health.current
	var seen := _count_emissions(health)

	b.begin_batch()
	b.add_modifier(_mod(&"health", 10.0))
	b.end_batch()

	assert_almost_eq(float(health.get_value()), before_max + 10.0, 0.001,
		"the cap must move by the modifier")
	assert_gt(seen.size(), 0, "a deferred pool notification must still arrive at end_batch")
	# heal_on_max_increase is on for `health` (D-21) and runs from
	# PoolStat._apply_max_change on the ADD path — not off value_changed — so
	# batching the signal must not swallow the grant.
	assert_almost_eq(health.current, before_current + 10.0, 0.001,
		"the cap-rise grant must survive batching")


func test_movement_points_modifier_in_a_batch_still_notifies() -> void:
	# Not hypothetical: procgen nodes really do roll `movement_points`, so this
	# is a SurplusPoolStat being modified inside the allocation batch.
	var b := _board()
	var mp := b.get_stat(&"movement_points") as PoolStat
	var before := float(mp.get_value())
	var seen := _count_emissions(mp)

	b.begin_batch()
	b.add_modifier(_mod(&"movement_points", 2.0))
	b.end_batch()

	assert_almost_eq(float(mp.get_value()), before + 2.0, 0.001)
	assert_gt(seen.size(), 0, "a SurplusPoolStat must not lose its notification to a batch")


func test_skill_point_claim_outside_a_batch_is_untouched() -> void:
	# force_allocate calls claim() BEFORE apply_entity_modifiers_to opens its
	# batch, so SP minting is on the unbatched path. Pin that it stays there.
	var b := _board()
	var sp := b.get_stat(&"skill_points") as SkillPointStat
	var seen := _count_emissions(sp)
	sp.claim(1)
	assert_gt(seen.size(), 0, "claim() outside a batch must notify immediately")
