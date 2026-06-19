@tool
class_name SkillPointStat
extends PoolStat

## SP — the entity's allocation budget. Four buckets sum to max:
##   `current` (spendable; inherited from PoolStat)
##   `used`    (locked into currently-allocated nodes)
##   `wounded` (forced out by attack; heals back over time)
##   `staked`  (spent to raise per-node allocation caps; recoverable via extract)
##
## Invariant: `used + current + wounded + staked == max`.
##
## Most operations are bucket *transfers* and leave max constant.
## Mint operations — `claim(N)` and `grant(N)` — increase total wealth:
##   - `claim(N)` mints into `used` (forced/free allocation: procgen setup,
##     starter nodes, scripted dev). The pool gains N max + 0 current.
##   - `grant(N)` mints into `current` (level-up). The pool gains N max + N current.
##
## NOTE: PoolStat's modifier-driven max is bypassed (get_value() override).
## Don't push StatModifierDef instances at `skill_points` — use grant() instead
## if you want to inject free SP, or claim() to inject locked-in SP.

signal used_changed
signal wounded_changed
signal staked_changed

@export var used: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if used == clamped:
			return
		used = clamped
		used_changed.emit()
		value_changed.emit()

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


## Pure bucket sum — modifiers and base_value are NOT consulted (see header).
func get_value() -> Variant:
	return used + roundi(current) + wounded + staked


## Order discipline: when raising current via a bucket transfer (refund / heal /
## extract), call set_current() FIRST, then decrement the source bucket.
## Otherwise the cap drops before current rises and PoolStat.set_current clamps
## us into a 1-SP leak. The inverse (current → bucket) is order-free because
## bumping the destination first only raises the cap.


## Spend N from current → used (gameplay allocate). Returns false if insufficient.
func spend(n: int) -> bool:
	if roundi(current) < n:
		return false
	used += n
	set_current(current - float(n))
	return true


## Refund N from used → current (voluntary deallocate).
func refund(n: int) -> void:
	var amount: int = min(n, used)
	set_current(current + float(amount))
	used -= amount


## Forced-deallocation by attack: transfer N from used → wounded.
## Used dropping mirrors the deallocated node leaving ownership; the SP doesn't
## flow back to current — caller (BattleSystem cascade) routes through here so
## "I had this SP-in-a-node, now it's hurt, not back in my hand" is one step.
func wound(n: int) -> void:
	var amount: int = min(n, used)
	wounded += amount
	used -= amount


## Heal N wounds: transfer wounded → current.
func heal(n: int) -> void:
	var amount: int = min(n, wounded)
	set_current(current + float(amount))
	wounded -= amount


## Stake N: transfer current → staked (raise a node's allocation cap).
## Returns false if insufficient current. Recovered via extract().
func stake(n: int) -> bool:
	if roundi(current) < n:
		return false
	staked += n
	set_current(current - float(n))
	return true


## Extract N staked SP back into current — the inverse of stake().
## (Gameplay-gated by core proximity etc; that gating lives at the call site.)
func extract(n: int) -> void:
	var amount: int = min(n, staked)
	set_current(current + float(amount))
	staked -= amount


## Mint N into used. Used by `force_allocate` for procgen / scripted setup —
## the entity gets a node for free; pool max bumps by N so subsequent
## deallocation refunds the SP into current without overflowing max.
func claim(n: int) -> void:
	used += n


## Mint N into current. Used by level-up: the player earned an SP.
## Pool max bumps by N (current is in the sum).
##
## Writes current directly because set_current() would clamp to the pre-write
## cap (= old current + used + W + S) — for a mint we *want* current to push
## past that. emits the same signals set_current would.
func grant(n: int) -> void:
	current += float(n)
	current_changed.emit(_coerce(current))
	value_changed.emit()


# --- PoolStat override --------------------------------------------------------
# We bypass the modifier-driven max entirely. _apply_max_change exists to react
# to modifier-driven cap changes — irrelevant here. set_current clamps to
# get_value(); since used/wounded/staked are in the sum, clamping is automatic.


func _apply_max_change(_old_max: float) -> void:
	# No-op: max is identity over buckets, not modifier-driven.
	pass
