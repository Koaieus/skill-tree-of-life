class_name CorruptionStatus
extends StatusDef

## Corruption (#964, hub #952): each turn tick deals `power × damage_per_power`
## of the node's MAX hp as unmitigated [constant DamageInstance.Type.TRUE]
## damage — the answer to bulk (owner, 2026-09-20: *"a fully corrupted lv1
## enemy would die too basically. the harsh reality of % damage"*). Halving
## decay and no cap are authored on the `.tres`; rarity comes from its
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


func _on_tick(_node: NodeCombat, _before: float, _after: float) -> void:
	pass


func projected_damage(_node: NodeCombat, _power: float) -> float:
	return 0.0
