class_name SpellDef
extends Resource

## Authored spell data — name, cost, and how its target is collected. The
## effect payload lives elsewhere (TBD when first spell ships); SpellDef is
## the static blueprint. MagicAttackPlan picks a SpellDef and delegates
## target-collection to its [member targeting].

@export var name: String
@export_multiline var description: String

@export var mana_cost: int = 0
## Scalar damage applied to the resolved target on commit. Damage application
## itself isn't wired yet — combat resolution lands later. Data shape now so
## spell .tres files don't need migration when it does.
@export var damage: int = 0

## How this spell's target is gathered + what counts as valid. The kind
## drives input dispatch (NODE click vs. world click); the predicates drive
## valid-target enumeration for highlight + AI.
@export var targeting: Targeting


func validate(_plan: MagicAttackPlan) -> Array[String]:
	var errors: Array[String] = []
	if targeting == null:
		errors.append(&"Spell has no targeting set")
	return errors


func _to_string() -> String:
	return "<SpellDef %s (%d mana)>" % [name, mana_cost]
