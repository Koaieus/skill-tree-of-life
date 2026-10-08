class_name CorruptionStatus
extends StatusDef

## Corruption: each turn tick deals `power × damage_per_power`
## of the node's MAX hp as unmitigated [constant DamageInstance.Type.TRUE]
## damage — the answer to bulk (owner, 2026-09-20: *"a fully corrupted lv1
## enemy would die too basically. the harsh reality of % damage"*). No decay
## (owner, 2026-10-01) and no cap are authored on the `.tres`; rarity comes from its
## sources and small stacks per hit, never from a clamp.
##
## Its own [StatusDef] subclass rather than a [PoisonStatus] with a basis
## flag — composition over inheritance — but the tick body is the shared
## [method DotTick.mint], so there is one implementation of "a DoT lands".
## The basis is not a knob here: corruption IS percent-of-max.
##
## Damage lands on the PRE-decay power (`_on_tick`'s `before`) — a status
## about to drop out this tick still deals its last hit.

## Fraction of max hp per point of power per tick (anchor 0.02: ten stacks
## take a fifth of any node). Owner-tuned on the `.tres`.
@export var damage_per_power: float = 0.02


func _on_tick(host, before: float, _after: float) -> void:
	DotTick.mint(host, before * damage_per_power, HitInstance.AmountBasis.PERCENT_MAX)


## Every remaining tick's damage as it will land, against max hp as of now —
## resisted and floored per tick ([method DotTick.project]): ten stacks at
## 0.02 on 2000 hp project 400 + 200 + 100 + 50 = 750.
func projected_damage(host, power: float) -> float:
	return DotTick.project(self, host, power, damage_per_power, HitInstance.AmountBasis.PERCENT_MAX)


func next_tick_damage(host, power: float) -> float:
	return DotTick.tick_damage(self, host, power, damage_per_power, HitInstance.AmountBasis.PERCENT_MAX)
