class_name PoisonStatus
extends StatusDef

## Poison (#874, hub #868 D3/D5): each turn tick deals unmitigated
## `DamageInstance.Type.TRUE` damage through [method NodeCombat.take_damage] —
## the same door attacks use, so `damaged` / regen-suppression / a killing
## `notify_depleted` all fire naturally (hub D6: *"Yes — ride notify_depleted
## now"*). `reapply = ACCUMULATE` in the authored def lets a volley build power
## (#495 is the arrow-borne follow-up, not this issue).
##
## [member basis] is a per-def knob (owner, 2026-09-14: *"doubt between %
## max node HP … and 'flat' … either way: not mitigated"*), and it is
## [member HitInstance.basis] itself rather than a poison-local enum: "flat
## or a fraction of the target's max hp" is a property of the damage, and
## [method DamageInstance.land_on] resolves it against the ticked slice —
## [constant HitInstance.AmountBasis.FLAT] deals `power_before *
## damage_per_power` HP; [constant HitInstance.AmountBasis.PERCENT_MAX] deals
## that product as a fraction of [method NodeCombat.get_max_hp], so a
## poisoned node's damage tracks its own health pool.
##
## Damage lands on the PRE-decay power (`_on_tick`'s `before`, never `after`) —
## a status about to drop to 0 this tick still deals its last hit; decay
## happens after this hook returns ([method NodeCombat.tick_statuses]).
##
## Unlike [ArmorBreakStatus] / `BlindnessStatus`, poison plants no modifier —
## `_on_applied` / `_on_removed` are both no-ops.

@export var basis: HitInstance.AmountBasis = HitInstance.AmountBasis.FLAT
## HP per point of power (FLAT), or fraction-of-max-hp per point of power
## (PERCENT_MAX). Multiplied by the tick's PRE-decay power either way.
@export var damage_per_power: float = 1.0


func _on_tick(node: NodeCombat, before: float, _after: float) -> void:
	var amount := before * damage_per_power
	if amount <= 0.0:
		return
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.basis = basis
	dmg.amount = amount
	dmg.target = node.host
	# Through `land_on`, the same door an attack's hit lands by, so the basis
	# resolves there and nowhere else. `CritRoll.apply` is a no-op for a hit
	# with no crit decided (multiplier 1.0) — a tick never crits.
	dmg.land_on(node, null)


## The sum of every remaining tick's damage under this def's own decay
## (#962, for #953's overlay): at 20 stacks halving, 20 + 10 + 5 + 2.5 + 1.25
## = 38.75 — the 0.625 tail is cut before it ticks. PERCENT_MAX resolves
## against the node's max hp as of now. A FLAT-decay poison sums its linear
## run-down the same way; a def that never decays is capped at one tick
## so the loop terminates.
func projected_damage(node: NodeCombat, power: float) -> float:
	var total := 0.0
	var p := power
	var guard := 0
	while p > 0.0 and guard < 1000:
		total += p * damage_per_power
		var next := decayed(p)
		if next >= p:
			break  # non-decaying def: one tick is all we can honestly project
		p = next
		guard += 1
	if basis == HitInstance.AmountBasis.PERCENT_MAX:
		total *= node.get_max_hp()
	return total
