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

## Which analytic/authored shape family a CARVE resolves to — the single
## selector InnerDisk switches on (replacing the old show_weld/show_diamond
## mutually-exclusive bool pair; see .claude/rules/skill-node-visuals.md).
## POLYGON/GEM are analytic (batch-friendly, no per-instance texture);
## TEXTURE is arbitrary art with no renderer yet (#245/#246) — InnerDisk falls
## back to an empty dome for it.
enum CarveStyle { POLYGON, GEM, TEXTURE }

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
var carve_style: CarveStyle = CarveStyle.TEXTURE
## Regular-polygon carve (the archetype fallback shape). 0 = not a polygon.
var polygon_sides: int = 0
## Anisotropic X-axis squish on the polygon carve (1.0 = regular).
var polygon_squish: float = 1.0
## Bitmap/atlas icon carve (spell grant, loot glyph, bespoke keystone).
var texture: Texture2D = null
## Parametric mark, drawn as a glow (the core-class sigil bloom).
var sigil: Sigil = null


## A regular-polygon CARVE — the shape family the batched dome shader can render
## as an analytic SDF (see [PolygonCarveShape] / the archetype fallback carved
## from [Archetype.carve_shape]).
static func polygon_carve(sides: int, prio: int, source: StringName, squish: float = 1.0) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.carve_style = CarveStyle.POLYGON
	e.polygon_sides = sides
	e.polygon_squish = squish
	e.source_kind = source
	return e


## The loot relic's gem-cut CARVE (#168) — see [GemCarveShape]. A fixed baked
## height-field dent, identical on every instance.
static func gem_carve(prio: int, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.carve_style = CarveStyle.GEM
	e.source_kind = source
	return e


## A bitmap/atlas-icon CARVE (arbitrary art: spell icon, loot glyph, keystone).
## No renderer exists yet (#245/#246) — InnerDisk falls back to an empty dome.
static func texture_carve(tex: Texture2D, prio: int, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.carve_style = CarveStyle.TEXTURE
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
