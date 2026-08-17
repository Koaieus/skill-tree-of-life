@tool
class_name SkillPointStat
extends PoolStat

## SP — the entity's allocation budget. Pure [PoolStat] (max comes from the
## modifier pipeline, current is clamped to it) plus two book-keeping buckets
## sitting *inside* max:
##   `wounded` — SP forced out of current by attack; recoverable via [method heal]
##   `staked`  — SP committed to per-node cap raises; recoverable via [method extract]
##
## A third bucket, `used`, is derived: `max - current - wounded - staked` — SP
## locked into the entity's currently-allocated nodes. Identity holds because
## the operations below either leave max alone (pure transfers) or grow it by
## the same amount they grow a bucket (mints).
##
## Modifiers on skill_points work exactly like on any other PoolStat: they
## participate in the pipeline computing max, and `heal_on_max_increase` on the
## def decides whether modifier-driven max changes also bump current. The mint
## operations bypass the modifier pipeline by writing base_value directly:
##   - `claim(N)`: max += N, current unchanged (the new SP lands in `used`).
##     Used by force_allocate — equivalent to "grant(N) then spend(N)" collapsed.
##   - `grant(N)`: max += N AND current += N. Used by level-up.

signal wounded_changed
signal staked_changed
## Delta signals carry the change amount (always positive). Use these for
## animation triggers (pulses, floaters); use [signal wounded_changed] /
## [signal staked_changed] for snapshot re-renders.
signal wounds_applied(amount: int)
signal wounds_healed(amount: int)
signal stake_applied(amount: int)
signal stake_extracted(amount: int)
## Fires every turn upkeep with the new [member wound_heal_progress] — the
## UI's wound-heal sliver binds here rather than polling.
signal wound_heal_progress_changed(progress: float)

## 0..1 fraction toward the next whole-SP heal tick. Runtime-only (not
## persisted) — accumulates [code]wound_heal_per_turn[/code] every turn
## upkeep even at fractional rates (e.g. 0.5/turn takes two turns to heal
## one SP), which plain `int(rate)` truncation would otherwise silently
## drop every turn. Held at 1.0 (capped, not wrapped) while [member wounded]
## is 0 — there's nothing to spend the credit on — so it reads "full" until
## the entity is wounded again, at which point the very next turn upkeep
## immediately heals and drains it. See [method _custom_turn_upkeep].
var wound_heal_progress: float = 0.0

@export var wounded: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if wounded == clamped:
			return
		wounded = clamped
		wounded_changed.emit()
		_emit_value_changed()

@export var staked: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if staked == clamped:
			return
		staked = clamped
		staked_changed.emit()
		_emit_value_changed()


## The three SP bins, exposed as formula accessors (see [method Stat.accessors]).
## `used` is derived but a read like the others — there is no write path through
## the modifier pipeline, and none should be added. Lambda parameters are typed
## `SkillPointStat` so a typo on `wounded` / `staked` / `used` fails at parse
## time rather than silently resolving to the wrong half (#333, Decision 5).
func accessors() -> Dictionary[StringName, Callable]:
	var d := super.accessors()
	d.merge({
		&"wounded": func(s: SkillPointStat): return s.wounded,
		&"staked": func(s: SkillPointStat): return s.staked,
		&"used": func(s: SkillPointStat): return s.used,
	})
	return d


## SP locked into currently-allocated nodes. Derived so the four buckets can't
## drift out of sync — if you find this returning a negative number, an
## operation violated the invariant (or someone set wounded/staked past max).
##
## Untyped (Variant) on purpose: typed computed properties get persisted as
## `used = null` in .tres files by the editor's resource serializer. Untyped
## computed properties (matching Stat.value's shape) stay runtime-only.
var used:
	get: return int(get_value()) - roundi(current) - wounded - staked


# --- Transfers (max preserved) ---------------------------------------------

## Spend N from current → used (gameplay allocate). Max unchanged because the
## SP shift from current into used is invisible to the derived `used` getter:
## current dropped, sum (max - current - W - S) rose. Returns false on shortfall.
func spend(n: int) -> bool:
	if roundi(current) < n:
		return false
	set_current(current - float(n))
	return true


## Refund N from used → current (voluntary deallocate).
func refund(n: int) -> void:
	var amount: int = min(n, used)
	set_current(current + float(amount))


## Forced-deallocation by attack: transfer N from used → wounded. Used drops
## (the node is gone), wounded climbs — SP doesn't return to current.
func wound(n: int) -> void:
	var amount: int = min(n, used)
	if amount <= 0:
		return
	wounded += amount
	wounds_applied.emit(amount)


## CUSTOM per-turn upkeep (skill_points.tres sets per_turn_mode = CUSTOM):
## heal `wound_heal_per_turn` worth of wounds — a bin transfer (wounded →
## current), not a pool top-up, which is why it can't be REFILL/ADD. Reads the
## rate off the board (the same sibling-stat coupling ADD pays for its companion).
##
## Accumulates fractionally (see [member wound_heal_progress]) instead of
## flooring the rate to an int every turn — a sub-1.0 rate would otherwise
## never heal anything.
func _custom_turn_upkeep(board: StatBoard) -> void:
	var rate_stat := board.get_stat(&"wound_heal_per_turn")
	var rate: float = float(rate_stat.get_value()) if rate_stat != null else 0.0
	if rate <= 0.0:
		return
	wound_heal_progress += rate
	while wound_heal_progress >= 1.0 and wounded > 0:
		heal(1)
		wound_heal_progress -= 1.0
	wound_heal_progress = minf(wound_heal_progress, 1.0)
	wound_heal_progress_changed.emit(wound_heal_progress)


## Heal N wounds: transfer wounded → current.
func heal(n: int) -> void:
	var amount: int = min(n, wounded)
	if amount <= 0:
		return
	wounded -= amount
	set_current(current + float(amount))
	wounds_healed.emit(amount)


## Stake N: transfer current → staked (raise a node's allocation cap).
func stake(n: int) -> bool:
	if roundi(current) < n:
		return false
	staked += n
	set_current(current - float(n))
	stake_applied.emit(n)
	return true


## Extract N staked SP back into current — the inverse of stake().
func extract(n: int) -> void:
	var amount: int = min(n, staked)
	if amount <= 0:
		return
	staked -= amount
	set_current(current + float(amount))
	stake_extracted.emit(amount)


# --- Mints (max grows) ------------------------------------------------------

## Bump max by N without raising current. The new SP lands in `used`
## (derived). Conceptually "grant(N) then spend(N)" collapsed atomically.
## Used by force_allocate for procgen / scripted setup.
##
## Writes `base_value` directly rather than going through the modifier path
## so heal_on_max_increase doesn't bump current — that's exactly what
## distinguishes claim from grant. This is the deliberate RAW door (D-31); the
## ratcheted sibling is [method PoolStat.set_base_ratcheted]. `skill_points.tres`
## opts *into* `heal_on_max_increase`, so this line is the only reason claim is a
## mint-max-only — don't "tidy" it into the ratcheted call.
func claim(n: int) -> void:
	base_value += float(n)
	_emit_value_changed()


## Bump max by N and raise current by N. Used by level-up — the player
## earned a fresh spendable SP.
func grant(n: int) -> void:
	base_value += float(n)
	current += float(n)
	current_changed.emit(_coerce(current))
	_emit_value_changed()
