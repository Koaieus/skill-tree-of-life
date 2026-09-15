class_name PoisonStatus
extends StatusDef

## Poison (#874, hub #868 D3/D5): each turn tick deals unmitigated
## `DamageInstance.Type.TRUE` damage through [method NodeCombat.take_damage] —
## the same door attacks use, so `damaged` / regen-suppression / a killing
## `notify_depleted` all fire naturally (hub D6: *"Yes — ride notify_depleted
## now"*). `reapply = ACCUMULATE` in the authored def lets a volley build power
## (#495 is the arrow-borne follow-up, not this issue).
##
## [member damage_mode] is a per-def knob (owner, 2026-09-14: *"doubt between %
## max node HP … and 'flat' … either way: not mitigated"*):
## [constant DamageMode.FLAT] deals `power_before * damage_per_power` HP;
## [constant DamageMode.PERCENT_MAX] deals that same product again scaled by
## [method NodeCombat.get_max_hp] — a fraction of the node's own max HP, not a
## fixed number, so a poisoned node's damage tracks its own health pool.
##
## Damage lands on the PRE-decay power (`_on_tick`'s `before`, never `after`) —
## a status about to drop to 0 this tick still deals its last hit; decay
## happens after this hook returns ([method NodeCombat.tick_statuses]).
##
## Unlike [ArmorBreakStatus] / `BlindnessStatus`, poison plants no modifier —
## `_on_applied` / `_on_removed` are both no-ops.

enum DamageMode {
	FLAT,
	## Scaled by [method NodeCombat.get_max_hp] in addition to `power_before`.
	PERCENT_MAX,
}

@export var damage_mode: DamageMode = DamageMode.FLAT
## HP per point of power (FLAT), or fraction-of-max-hp per point of power
## (PERCENT_MAX). Multiplied by the tick's PRE-decay power either way.
@export var damage_per_power: float = 1.0


func _on_tick(node: NodeCombat, before: float, _after: float) -> void:
	var amount := before * damage_per_power
	if damage_mode == DamageMode.PERCENT_MAX:
		amount *= node.get_max_hp()
	if amount <= 0.0:
		return
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.amount = amount
	dmg.target = node.host
	node.take_damage(amount, dmg)
