class_name EmblemSpec
extends RefCounted
## One candidate for a SkillNode's central emblem, contributed by a node source
## (archetype, keystone, spell grant, loot addon, or core presence). Each source
## hands back an [EmblemSpec]; an [EmblemResolver] decides which CARVE wins and
## which BLOOMs draw — so SkillNode never has to know what a spell, a keystone,
## or a loot relic is. See SKILLNODE_EMBLEM_HANDOFF.md for the full model.

## Which visual register this emblem draws in. CARVE = the single height-field
## dent in the dome (one winner, chosen by [member priority]). BLOOM = an
## additive, entity-tinted glow layered over the dome; many may coexist and
## they never compete for the carve (that's how core presence rides alongside a
## carved spell/loot glyph on the same node).
enum Register { CARVE, BLOOM }

## How the emblem is tinted at draw time.
enum TintMode { ARCHETYPE, ENTITY, FIXED }

## CARVE priority ladder — higher wins. Ordering per the locked design:
## keystone (bespoke) > loot (consumed one-off) > spell grant > archetype shape
## (the fallback). BLOOM carries no meaningful priority.
const PRIORITY_ARCHETYPE := 10
const PRIORITY_SPELL := 20
const PRIORITY_LOOT := 30
const PRIORITY_KEYSTONE := 40

var register: Register = Register.CARVE
var priority: int = PRIORITY_ARCHETYPE
var tint_mode: TintMode = TintMode.ARCHETYPE
var fixed_tint: Color = Color.WHITE
## Where this contribution came from — for tie-break debugging and tooltip copy.
var source_kind: StringName = &""

# --- visual payload: a spec carries whichever field its kind needs ---
## Regular-polygon carve (the archetype fallback shape). 0 = not a polygon.
var polygon_sides: int = 0
## Bitmap/atlas icon carve (spell grant, loot glyph, bespoke keystone).
var texture: Texture2D = null
## Parametric mark, drawn as a glow (the core-class sigil bloom).
var sigil: Sigil = null


## A regular-polygon CARVE — the shape family the batched dome shader can render
## as an analytic SDF (see the archetype fallback in [ArchetypeShape]).
static func polygon_carve(sides: int, prio: int, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.polygon_sides = sides
	e.source_kind = source
	return e


## A bitmap/atlas-icon CARVE (arbitrary art: spell icon, loot glyph, keystone).
static func texture_carve(tex: Texture2D, prio: int, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.texture = tex
	e.source_kind = source
	return e


## A BLOOM contribution: a parametric mark drawn as an entity-tinted glow — the
## core-class sigil beacon. Never competes for the carve.
static func sigil_bloom(mark: Sigil, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.BLOOM
	e.tint_mode = TintMode.ENTITY
	e.sigil = mark
	e.source_kind = source
	return e
