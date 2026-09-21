class_name BladeStatusInstance
extends StatusInstance

## The status half of a toxic vertex's contact (#951) — [BladeDamageInstance]'s
## partner, appended right after it by [SwingResolve] with the same
## `structural_key`, so it lands on the same beat, after the damage. It applies
## iff its damage hit was ADMITTED by the live gate: it never asks the gate
## itself — a second `admit` of the same event can pop the vertex twice — it
## reads the admission its damage hit recorded. A refused contact lands as a
## power-0 dud the record carries and [method NodeCombat.apply_status] ignores
## on replay, the [RangedDamageFormula.RangedStatusInstance] shape.
##
## Never rebuilt by [AttackRecord] — a peer lands a plain [StatusInstance] at
## the authority's landed power, exactly as for an arrow's poison.

var _damage: BladeDamageInstance


func _init(damage: BladeDamageInstance = null) -> void:
	super._init()
	_damage = damage


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	if _damage == null or not _damage.admitted:
		gated = true
		power = 0.0
		amount = 0.0
		effective_amount = 0.0
		return
	super.land_on(node, world)
