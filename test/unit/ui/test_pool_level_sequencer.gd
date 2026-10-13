extends GutTest

## PoolLevelSequencer (#317) — turning an XP pool's synchronous multi-level
## cascade into an ordered replay queue.
##
## The reason this class exists at all is signal ORDER: a `replenish()` that
## crosses several levels recurses, so `replenished` fires deepest-level-first
## as the recursion unwinds, while `value_changed` fires in true ascending
## order. Everything below drives a REAL PoolStat rather than a hand-fed
## snapshot list, so the ordering being tested is the engine's, not the test's.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _xp: PoolStat
var _seq: PoolLevelSequencer
## The first three xp caps off a fresh board.
var _c1: float
var _c2: float
var _c3: float


func before_each() -> void:
	# Default XP pool: a GrowablePoolStatDef in post_grow_mode OVERFLOW. The
	# caps are read off its growth (a tuned knob), never pinned here.
	var board: EntityStatBoard = _BOARD.duplicate(true)
	_xp = board.xp
	var def := _xp.definition as GrowablePoolStatDef
	_c1 = float(_xp.value)
	_c2 = float(_xp._coerce(_c1 * def.growth_factor + def.growth_flat))
	_c3 = float(_xp._coerce(_c2 * def.growth_factor + def.growth_flat))
	_seq = PoolLevelSequencer.new(float(_xp.value))
	_xp.value_changed.connect(func(): _seq.observe(float(_xp.current), float(_xp.value)))


func _fill_tos() -> Array:
	return _seq.pending().map(func(s): return s.fill_to)


func _new_maxes() -> Array:
	return _seq.pending().map(func(s): return s.new_max)


func test_a_gain_that_crosses_nothing_records_no_segment() -> void:
	_xp.replenish(3.0)
	assert_false(_seq.has_pending(), "3 XP under the first cap is not a level")


func test_one_level_records_one_segment() -> void:
	_xp.replenish(_c1 + 2.0)
	assert_eq(_fill_tos(), [_c1], "fill to the cap that was reached")
	assert_eq(_new_maxes(), [_c2], "then adopt the grown cap")
	assert_eq(float(_xp.current), 2.0, "model already carried the overflow (sanity)")


## The heart of it: `replenished` would report these levels backwards.
func test_a_two_level_cascade_records_ascending_segments() -> void:
	_xp.replenish(_c1 + _c2 + 5.0)
	assert_eq(_fill_tos(), [_c1, _c2], "ASCENDING — the order the bar must play")
	assert_eq(_new_maxes(), [_c2, _c3], "each segment ends on its own new cap")


func test_replenished_really_does_fire_backwards() -> void:
	# Guards the premise of this whole class: if PoolStat ever stopped
	# unwinding in reverse, the sequencer's `value_changed` sourcing would
	# still be correct but this comment (and the rule file) would be stale.
	var caps_at_replenished: Array = []
	_xp.replenished.connect(func(): caps_at_replenished.append(float(_xp.value)))
	_xp.replenish(_c1 + _c2 + 5.0)
	assert_eq(caps_at_replenished, [_c3, _c3],
			"both fire only after the cascade bottomed out — reverse unwind, no per-level state")


func test_a_second_grant_appends_rather_than_resetting() -> void:
	_xp.replenish(_c1 + 2.0)
	assert_eq(_fill_tos(), [_c1], "one level so far")
	# Nothing consumed the queue yet — the replay is still mid-flight. A second
	# grant must extend it, not restart from a stale view of the pool.
	_xp.replenish(_c2 - 2.0 + _c3 + 7.0)
	assert_eq(_fill_tos(), [_c1, _c2, _c3], "extended in place, still ascending")


func test_popping_drains_in_order() -> void:
	_xp.replenish(_c1 + _c2 + 5.0)
	assert_eq(_seq.pop().fill_to, _c1)
	assert_eq(_seq.pop().fill_to, _c2)
	assert_null(_seq.pop(), "drained")
	assert_false(_seq.has_pending())


## A cap raised by the modifier pipeline is not a level-up: `current` is
## somewhere below the old cap when it happens, which is exactly what the
## sequencer's guard tests for.
func test_a_modifier_driven_cap_rise_is_not_a_level() -> void:
	_xp.replenish(2.0)
	var m := StatModifier.new()
	m.stat_id = &"xp"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 10.0
	_xp.add_modifier(m)
	assert_eq(float(_xp.value), _c1 + 10.0, "cap did rise (sanity)")
	assert_false(_seq.has_pending(), "but nothing filled, so nothing to replay")


## The seed matters: starting `_last_cap` at 0 would make the first observed
## cap rise satisfy both guards (cap > 0, current == 0) and record a phantom
## segment — a tween to zero plus a spurious LEVEL UP.
func test_a_cap_rise_before_any_xp_lands_records_nothing() -> void:
	var m := StatModifier.new()
	m.stat_id = &"xp"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 10.0
	_xp.add_modifier(m)
	assert_false(_seq.has_pending(), "an empty pool whose cap grew has not levelled")


func test_reset_drops_pending_segments() -> void:
	_xp.replenish(_c1 + _c2 + 5.0)
	_seq.reset(float(_xp.value))
	assert_false(_seq.has_pending(), "rebinding to another entity starts clean")
