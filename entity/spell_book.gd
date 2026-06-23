@tool
class_name SpellBook
extends Resource

## A character's known spells, plus the gating logic that turns
## "knows spell X" into "can cast X from node N right now". Centralising those
## rules here keeps [MagicAttackPlan] and the spell-picker UI in agreement —
## both ask the same question, both get the same answer.
##
## Authored as a .tres per character archetype (apprentice spellbook, archmage
## spellbook…) and assigned to [member Entity.spellbook]; runtime sandboxes
## that don't bother with a .tres can build one with [code]SpellBook.new()[/code]
## + push spells into [member spells].

@export var spells: Array[SpellDef] = []


## Spells whose source-side constraints are satisfied at [param source] for
## [param attacker]. Mana check is NOT included here — that's per-cast and the
## caller (MagicAttackPlan.validate / spell-picker enable state) layers it on.
func castable_from(source: SkillNode, attacker: Entity) -> Array[SpellDef]:
	var result: Array[SpellDef] = []
	for spell in spells:
		if spell != null and _node_meets_source_requirements(spell, source, attacker):
			result.append(spell)
	return result


## Does the entity's owned-subgraph degree at [param source] satisfy
## [param spell]'s [member SpellDef.min_degree]? Returns true for null source
## (the UI uses this to decide "can EVER be cast" before a source is picked).
func is_castable(spell: SpellDef, source: SkillNode, attacker: Entity) -> bool:
	if spell == null:
		return false
	if source == null:
		# Pre-source state: don't grey-out spells, just enable them — the
		# real gate fires once a source is selected.
		return true
	return _node_meets_source_requirements(spell, source, attacker)


func _node_meets_source_requirements(spell: SpellDef, source: SkillNode,
		attacker: Entity) -> bool:
	if attacker == null or attacker.navigator == null:
		# Conservative default: without a navigator we can't measure degree;
		# assume gating fails so we don't promise an invalid cast.
		return false
	if source.owned_by != attacker:
		return false
	var deg := attacker.navigator.get_degree(source)
	return deg >= spell.min_degree


## Convenience for tests / scripted setup — appends a spell if absent.
## Editor-safe (no scene-tree access).
func learn(spell: SpellDef) -> void:
	if spell == null or spell in spells:
		return
	spells.append(spell)
	emit_changed()
