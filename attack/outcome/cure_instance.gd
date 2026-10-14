class_name CureInstance
extends HitInstance

## One landing of a cleanse: the exact stacks it clears per status and the
## HP those clears buy. Pure data until [method land_on] — the counts were
## decided at resolve, on the world the walk read, and land applies them
## VERBATIM: no re-read of the node's stacks, no clamp. Re-deciding here would
## let the landing disagree with the drain that already passed the leftover on.
##
## Never crits ([method draws_own_crit] false, no [method CritRoll.apply]): a
## crit would clear more than the drain planned and desync the leftover.
##
## On the wire ([AttackRecord]) the defs ride as `resource_path`s, the counts
## beside them, and [member heal] rides the generic amount column — so a def
## with no backing `.tres` cannot survive a record round trip.

## The statuses this landing clears, parallel to [member cleared], in the
## order the cure table cleared them.
var defs: Array[StatusDef] = []
## Whole stacks removed per entry of [member defs].
var cleared := PackedFloat64Array()
## Per entry of [member defs]: 1 when the clear comes off the core (the
## landed node's owner's entity row), 0 when off the node.
var on_core := PackedByteArray()
## HP healed on landing, through [method NodeCombat.heal_damage]; 0 heals nothing.
var heal: float = 0.0


func _init() -> void:
	kind = Kind.CURE


## Append one status's planned clear.
func add(def: StatusDef, count: float, core: bool = false) -> void:
	defs.append(def)
	cleared.append(count)
	on_core.append(1 if core else 0)


func draws_own_crit() -> bool:
	return false


## Clear each planned count off [param node], then heal [member heal] through
## [method NodeCombat.heal_damage] with this instance as the source. The heal
## is stamped onto [member HitInstance.amount] / [member
## HitInstance.effective_amount] first: [method NodeCombat.heal_damage] only
## writes the latter back for a [HealInstance], and [AttackRecord] ships it.
func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	amount = heal
	effective_amount = heal
	for i in defs.size():
		node.adjust_status_power(defs[i], -cleared[i])
	if heal > 0.0:
		node.heal_damage(heal, self)


func _to_string() -> String:
	return "<CureInstance %s heal %.1f → %s>" % [cleared, heal, target]
