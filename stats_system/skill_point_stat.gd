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

@export var wounded: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if wounded == clamped:
			return
		wounded = clamped
		wounded_changed.emit()
		value_changed.emit()

@export var staked: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if staked == clamped:
			return
		staked = clamped
		staked_changed.emit()
		value_changed.emit()


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
	wounded += amount


## Heal N wounds: transfer wounded → current.
func heal(n: int) -> void:
	var amount: int = min(n, wounded)
	wounded -= amount
	set_current(current + float(amount))


## Stake N: transfer current → staked (raise a node's allocation cap).
func stake(n: int) -> bool:
	if roundi(current) < n:
		return false
	staked += n
	set_current(current - float(n))
	return true


## Extract N staked SP back into current — the inverse of stake().
func extract(n: int) -> void:
	var amount: int = min(n, staked)
	staked -= amount
	set_current(current + float(amount))


# --- Mints (max grows) ------------------------------------------------------

## Bump max by N without raising current. The new SP lands in `used`
## (derived). Conceptually "grant(N) then spend(N)" collapsed atomically.
## Used by force_allocate for procgen / scripted setup.
##
## Writes `base_value` directly rather than going through the modifier path
## so heal_on_max_increase doesn't bump current — that's exactly what
## distinguishes claim from grant.
func claim(n: int) -> void:
	base_value += float(n)
	value_changed.emit()


## Bump max by N and raise current by N. Used by level-up — the player
## earned a fresh spendable SP.
func grant(n: int) -> void:
	base_value += float(n)
	current += float(n)
	current_changed.emit(_coerce(current))
	value_changed.emit()
