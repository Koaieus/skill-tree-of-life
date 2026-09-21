class_name SpellCatalog
extends RefCounted

## [member SpellDef.id] -> the authored [SpellDef], for the wire (#511).
##
## Deliberately a separate class rather than a static on [SpellDef], for the
## same reason [CommandCodec] is separate from [Command]: a script that
## `preload`s resources whose `script_class` is itself is a parse-time cycle.
## If you see "Could not find type SpellDef" here, that is the cycle talking,
## not a stale class cache.
##
## Deliberately NOT an autoload registry either — a const list of authored
## things with an id lookup over it. Adding a spell is one line here and one
## `id` in its `.tres`. ([TempUpgradeCatalog] is the same lookup as an
## authored `.tres` reached through an `@export` — the inspector-composable
## shape this const list should grow into; #1026.)

const SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const BRUISER: SpellDef = preload("res://attack/spell/defs/bruiser.tres")
const RESONATOR: SpellDef = preload("res://attack/spell/defs/resonator.tres")
const LEAFBLOWER: SpellDef = preload("res://attack/spell/defs/leafblower.tres")
const REVERBERATOR: SpellDef = preload("res://attack/spell/defs/reverberator.tres")
const HEALING_BEAM: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")
const TRAIL_BLAZER: SpellDef = preload("res://attack/spell/defs/trail_blazer.tres")
const LIGHTNING_BOLT: SpellDef = preload("res://attack/spell/defs/lightning_bolt.tres")
const CYCLONE: SpellDef = preload("res://attack/spell/defs/cyclone.tres")
const DAZZLE: SpellDef = preload("res://attack/spell/defs/dazzle.tres")
const SUNDER: SpellDef = preload("res://attack/spell/defs/sunder.tres")
const VENOM: SpellDef = preload("res://attack/spell/defs/venom.tres")
const HEX: SpellDef = preload("res://attack/spell/defs/hex.tres")

## Every authored spell. Order is not a contract — [member SpellDef.id] is.
const ALL: Array[SpellDef] = [
	SPARK, BRUISER, RESONATOR, LEAFBLOWER,
	REVERBERATOR, HEALING_BEAM, TRAIL_BLAZER, LIGHTNING_BOLT,
	CYCLONE, DAZZLE, SUNDER, VENOM, HEX,
]


## The authored def named by [param id], or null if there is none. Returns the
## CONST resource itself, never a copy, so identity comparisons against
## [constant ALL] entries (and against a plan's live `spell`) keep working.
static func by_id(id: StringName) -> SpellDef:
	if id == &"":
		return null
	for spell in ALL:
		if spell.id == id:
			return spell
	return null
