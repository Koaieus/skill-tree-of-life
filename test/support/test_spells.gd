class_name TestSpells
extends RefCounted

## The authored [SpellCatalog] and the shipped defs tests name, for fixtures.
## Production code reaches the catalog through an `@export` instead; a test
## that builds a system by hand assigns [constant CATALOG] to it. Each def is
## the same instance [method SpellCatalog.by_id] returns (one resource cache).

const CATALOG: SpellCatalog = preload("res://attack/spell/spell_catalog.tres")

const SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const RESONATOR: SpellDef = preload("res://attack/spell/defs/resonator.tres")
const LEAFBLOWER: SpellDef = preload("res://attack/spell/defs/leafblower.tres")
const HEALING_BEAM: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")
const LIGHTNING_BOLT: SpellDef = preload("res://attack/spell/defs/lightning_bolt.tres")
const SCOUT_LINE: SpellDef = preload("res://attack/spell/defs/scout_line.tres")
const POCKET_SAND: SpellDef = preload("res://attack/spell/defs/pocket_sand.tres")
