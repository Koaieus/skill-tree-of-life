@tool
class_name SpellCatalog
extends Resource

## Every authored [SpellDef], and the [member SpellDef.id] -> def lookup the
## wire resolves through (#511). Authored as `attack/spell/spell_catalog.tres`
## and reaching consumers through an `@export` wired by the composing scene
## ([member CommandApplier.spell_catalog] -> [member CommandContext.spell_catalog]
## for the command path, [member LootSystem.spell_catalog], the snapshot's
## restore argument, [member SpellCatalogueList.catalog]) — never a static door,
## so the list is inspector-composable.
##
## Never `preload` the `.tres` from this script: a script that `preload`s a
## resource whose `script_class` is itself is a parse-time cycle ("Could not
## find type SpellCatalog" is the cycle talking, not a stale class cache).
##
## Adding a spell: author its def under `attack/spell/defs/` with a unique
## `id`, then append it to [member spells] in the `.tres`
## (`test_spell_catalog.gd` fails until you do).

## Every authored spell, in catalogue (UI) order. Order is not a wire
## contract — [member SpellDef.id] is.
@export var spells: Array[SpellDef] = []


## The authored def named by [param id], or null if there is none. Returns the
## shared resource itself, never a copy — the resource cache hands the same
## instance to any `load()` of the def's path — so identity comparisons
## against a plan's live `spell` keep working.
func by_id(id: StringName) -> SpellDef:
	if id == &"":
		return null
	for spell in spells:
		if spell != null and spell.id == id:
			return spell
	return null
