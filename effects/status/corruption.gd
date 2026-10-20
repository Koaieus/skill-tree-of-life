@tool
class_name CorruptionStatus
extends StatusDef

## Corruption: a pile that hurts only when it TOPPLES. Each topple of a host
## at threshold `T` ([SandpileSpread]) deals `T × damage_per_power` of the
## node's MAX hp as unmitigated [constant DamageInstance.Type.TRUE] damage
## ([method _on_burst]) — the answer to bulk (owner, 2026-09-20: *"a fully
## corrupted lv1 enemy would die too basically. the harsh reality of %
## damage"*). Nothing ticks: a turn end deals no damage, so the projections
## read 0 (owner, 2026-10-11: damage only on topple). No decay (owner,
## 2026-10-01) and no cap are authored on the `.tres`; rarity comes from its
## sources and small stacks per hit, never from a clamp.
##
## Its own [StatusDef] subclass rather than a [PoisonStatus] with a basis
## flag — composition over inheritance — but the burst is the shared
## [method DotTick.mint], so there is one implementation of "a DoT lands".
## The basis is not a knob here: corruption IS percent-of-max.

## Fraction of max hp per unit of threshold per topple (`X`; anchor 0.02).
## Owner-tuned on the `.tres`.
@export var damage_per_power: float = 0.02


## [param topples] pops at threshold [param threshold]: one TRUE hit of
## `topples × threshold × damage_per_power` of max hp.
func _on_burst(host, topples: int, threshold: int) -> void:
	DotTick.mint(host, burst_amount(host, topples, threshold), HitInstance.AmountBasis.FLAT)


## The HP [param topples] pops at [param threshold] land on [param host]:
## `topples × threshold × damage_per_power × max hp`, rounded up once by
## [method HitPoints.whole] as the door rounds it. [method _on_burst] mints
## exactly this, so a readout drawing it cannot drift from what lands.
func burst_amount(host, topples: int, threshold: int) -> float:
	var amount := float(topples * threshold) * damage_per_power * float(host.get_max_hp())
	return HitPoints.whole(amount) if amount > 0.0 else 0.0


## [param stacks] cleansed are worth one topple at that threshold —
## [method burst_amount], so the 2% lives in one place. Counts are whole.
func cleanse_worth(host, stacks: float) -> float:
	return burst_amount(host, 1, int(roundf(stacks)))


## A tick deals nothing: corruption only hurts on a topple.
func _on_tick(_host, _before: float, _after: float) -> void:
	pass


## Nothing ticks, so nothing is projected.
func projected_damage(_host, _power: float) -> float:
	return 0.0


func next_tick_damage(_host, _power: float) -> float:
	return 0.0
