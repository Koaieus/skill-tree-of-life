class_name PoolLevelSequencer
extends RefCounted

## Replay timeline for a [GrowablePoolStatDef] pool (XP today). Turns the
## pool's synchronous multi-level cascade into an ordered queue of "one level"
## segments a [PoolGauge] can play back one at a time.
##
## [b]Feed it from [signal Stat.value_changed], never from [signal
## PoolStat.replenished.[/b] A single `replenish()` that crosses several levels
## recurses, so `replenished` fires in REVERSE chronological order as the
## recursion unwinds — the deepest level's first. `value_changed` fires at the
## point `base_value` is written, before the recursive `set_current`, so across
## the cascade it arrives in true ascending order. See
## `.claude/rules/stats-system.md` → "`replenished` fires in REVERSE
## chronological order across a cascade".
##
## The model stays authoritative and instant: this only records what to replay.
## Nothing in gameplay should ever wait on it.

## One level crossing: fill the bar to `fill_to` (the cap that was just
## reached), announce, wrap to empty, then adopt `new_max` as the cap.
class Segment extends RefCounted:
	var fill_to: float
	var new_max: float

	func _init(p_fill_to: float, p_new_max: float) -> void:
		fill_to = p_fill_to
		new_max = p_new_max


var _pending: Array[Segment] = []
var _last_cap: float


## [param starting_cap] must be the pool's CURRENT cap, not zero. Seeded at
## zero, the very first cap rise observed while `current` is still 0 satisfies
## both guards in [method observe] (`cap > 0` and `current == 0`) and records a
## phantom `{0 -> cap}` segment, which plays back as a tween to zero plus a
## spurious level-up announcement. Ordinary XP gains dodge that only because
## `current` has already moved off 0; a cap-affecting modifier applying before
## the first XP tick does not.
func _init(starting_cap: float) -> void:
	_last_cap = starting_cap


## Feed one `(current, cap)` snapshot, taken inside a `value_changed` handler.
## Records a segment iff the cap grew AND `current` is parked exactly on the
## old cap — which is true of a level crossing and nothing else: under
## [constant GrowablePoolStatDef.PostGrowMode.OVERFLOW], `on_pool_filled`
## writes the grown `base_value` (emitting `value_changed`) while `current` is
## still sitting at the cap it just filled. A modifier-driven cap rise moves
## the cap with `current` somewhere below it, and is correctly ignored.
func observe(current: float, cap: float) -> void:
	if cap > _last_cap and is_equal_approx(current, _last_cap):
		_pending.append(Segment.new(_last_cap, cap))
	_last_cap = cap


## How many segments are still queued. The driver divides its replay budget by
## this (plus the one it is about to play) to pace a cascade — see
## [method PoolGauge.play_level_segment].
func pending_count() -> int:
	return _pending.size()


func has_pending() -> bool:
	return not _pending.is_empty()


func peek() -> Segment:
	return _pending[0] if not _pending.is_empty() else null


func pop() -> Segment:
	return _pending.pop_front() if not _pending.is_empty() else null


## Drop every recorded segment and re-seed the cap. For rebinding to a
## different entity — stale segments would otherwise replay against the new
## pool.
func reset(starting_cap: float) -> void:
	_pending.clear()
	_last_cap = starting_cap


## Read-only view, for tests and debugging.
func pending() -> Array[Segment]:
	return _pending.duplicate()
