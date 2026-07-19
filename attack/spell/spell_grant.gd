@tool
class_name SpellGrant
extends Effect

## Grants a spell to the owning entity while this effect is active. When a node
## carrying a [SpellGrant] is allocated, the spell enters the entity's [SpellBook];
## when the node is deallocated (including forced-dealloc cascades), the spell
## drops — unless the same spell is also granted by another held node (ref-counted).
##
## Spells on the core node are permanent until death; spells on territory nodes
## are territorial incentives — hold the node, hold the spell.

@export var spell_def: SpellDef


func _on_granted(ctx: EffectContext) -> void:
	super._on_granted(ctx)
	if spell_def == null or ctx.entity == null:
		return
	# TODO: maybe if no spellbook then "granting" should be a no-op?
	_ensure_spellbook(ctx.entity).add_spell(spell_def, ctx.source_node)


func _on_revoked(ctx: EffectContext) -> void:
	if spell_def != null and ctx.entity != null:
		var book := ctx.entity.spellbook
		if book != null:
			book.remove_spell(spell_def, ctx.source_node)
	super._on_revoked(ctx)


func _ensure_spellbook(entity: Entity) -> SpellBook:
	if entity.spellbook == null:
		entity.spellbook = SpellBook.new()
	return entity.spellbook
