@tool
class_name SurplusPoolStat
extends PoolStat

## A [PoolStat] carrying one extra bin — `surplus` — that sits *outside* the cap.
##
## Where [SkillPointStat]'s bins (`wounded`/`staked`) live *inside* max, surplus
## lives beyond it:
##     available() == current + surplus     # may exceed .value
##
## Surplus is a **transient budget boost** (see #152): "you have N extra
## deallocation/movement points this turn". It is deliberately outside two
## systems that would otherwise stomp it:
##   - `restore_to_full()` only moves `current` against the cap, so a turn-start
##     REFILL leaves surplus untouched.
##   - The modifier pipeline never consults it — no `heal_on_max_increase`, no
##     `SET`-short-circuit. A `SET cap = 0` pool with nonzero surplus is a legal,
##     meaningful state (an entity whose whole budget is bought with unspent AP).
## Cap changes never clamp surplus; it isn't bounded by the cap.
##
## Contract: surplus is **overwritten each turn, never accumulated** (an idle
## entity must not compound it) — write it with [method set_surplus], never an
## `add_surplus`. It does not survive its turn: written at turn end, spent
## surplus-first or lost during the following turn.

signal surplus_changed

@export var surplus: int = 0:
	set(v):
		var clamped: int = max(0, v)
		if surplus == clamped:
			return
		surplus = clamped
		surplus_changed.emit()
		value_changed.emit()


## The out-of-cap surplus bin plus the spendable-this-turn `available()` —
## exposed as formula accessors (see [method Stat.accessors]). Lambda
## parameters are typed `SurplusPoolStat` so a typo on `surplus` / `available`
## fails at parse time rather than silently resolving to the wrong half
## (#333, Decision 5).
func accessors() -> Dictionary[StringName, Callable]:
	var d := super.accessors()
	d.merge({
		&"surplus": func(s: SurplusPoolStat): return s.surplus,
		&"available": func(s: SurplusPoolStat): return s.available(),
	})
	return d


## Overwrite the surplus bin. Overwrites, never accumulates (see class contract):
## a turn ending with 0 unused budget writes 0, clearing last turn's surplus.
func set_surplus(n: int) -> void:
	surplus = max(0, n)


## Total spendable this turn: `current` plus the transient surplus. May exceed
## the cap (`.value`). A method, not a computed property — typed computed props
## get persisted as `null` in .tres (see [member SkillPointStat.used]).
func available() -> int:
	return roundi(current) + surplus


## Surplus-first spend order (burn-it-or-lose-it): draw `surplus` to zero before
## touching `current`, so the boost is spent on travel or wasted and the ordinary
## budget survives an idle turn intact. Negative / zero amounts fall through to
## the base [method PoolStat.set_current] path unchanged.
func deplete(amount: float) -> void:
	if amount <= 0.0 or surplus <= 0:
		super(amount)
		return
	var from_surplus := minf(float(surplus), amount)
	surplus = surplus - int(from_surplus)
	var remainder := amount - from_surplus
	if remainder > 0.0:
		super(remainder)
