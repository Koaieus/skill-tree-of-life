@tool
class_name SkillPointStat
extends PoolStat

## SP — the entity's allocation budget. Three buckets sum to max:
##   `current` (spendable mana — inherited from PoolStat)
##   `wounded` (forced-out by attack; unusable until healed)
##   `used`    (currently invested in allocated nodes — derived externally
##              from the allocation count, not tracked here)
## Invariant: `used + current + wounded == max`.
##
## Buffer-tap temporary SP (battle-phase only) and the per-allocation
## "is this temp?" tagging live in the AllocationSystem / TurnManager,
## not here — so the stat stays a simple resource pool.

signal wounded_changed

@export var wounded: int = 0:
	set(value):
		var clamped: int = max(0, value)
		if wounded == clamped:
			return
		wounded = clamped
		wounded_changed.emit()


## Spend N from current. Returns false if insufficient — caller's gate, not
## the stat's responsibility to surface to the player.
func spend(n: int) -> bool:
	if current < n:
		return false
	set_current(current - n)
	return true


## Normal-deallocation refund: N returns to current.
func refund(n: int) -> void:
	set_current(current + n)


## Forced-deallocation by attack: N units become wounded. `used` decreases
## (the node is now deallocated) but `current` is unchanged — the SP doesn't
## flow back to the mana bar.
func wound(n: int) -> void:
	wounded += n


## Heal N wounds — they return to current as spendable mana.
func heal(n: int) -> void:
	var amount: int = min(n, wounded)
	wounded -= amount
	set_current(current + amount)
