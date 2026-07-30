class_name EmblemSpec
extends RefCounted
## One candidate for a SkillNode's central emblem, contributed by a node source
## (archetype, keystone, spell grant, loot addon, or core presence). Each source
## hands back an [EmblemSpec]; an [EmblemResolver] decides which CARVE wins and
## which BLOOMs draw — so SkillNode never has to know what a spell, a keystone,
## or a loot relic is. See docs/domain/skillnode-emblem.md for the full model.

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
##
## A rung is deliberately SHAREABLE — [member source_kind] is a separate field,
## not this enum's name: `node_visuals_composite.gd` contributes `&"authored"`
## at [constant Priority.ARCHETYPE], and [EmblemResolver] models `carve_ties`
## for specs tied at the winning rung. Don't collapse the two.
enum Priority {
	ARCHETYPE = 10,
	SPELL = 20,
	LOOT = 30,
	KEYSTONE = 40,
}

var register: Register = Register.CARVE
## Left as a plain [int] (not [enum Priority]) so a caller may sit between two
## rungs without minting an enum member; [EmblemResolver] only ever compares it.
var priority: int = Priority.ARCHETYPE
var tint_mode: TintMode = TintMode.ARCHETYPE
var fixed_tint: Color = Color.WHITE
## Where this contribution came from — for tie-break debugging and tooltip copy.
var source_kind: StringName = &""

## The shape this CARVE etches — the [CarveShape] ITSELF, not a copy of its
## fields. Whatever renders the emblem dispatches on the shape's own type
## ([InnerDisk.set_carve]), so adding a parameter to a shape family is one edit
## on that shape rather than a new payload field here plus a new copy hop there.
##
## Null is meaningful and NOT the same as "no contribution": it means this
## source claims the carve at its rung but has no shape authored yet (a keystone
## or spell whose `carve_shape` is unset), which renders as an empty dome —
## honest, rather than letting the archetype fallback misrepresent the node.
var shape: CarveShape = null
## Parametric mark, drawn as a glow (the core-class sigil bloom). Its own
## register — a [Sigil] is not a [CarveShape] and never competes for the carve.
var sigil: Sigil = null


## The one CARVE constructor. Reached through [method CarveShape.carve], which
## is the entry point every source uses — this stays public for the sources that
## have no shape to hand over (see [member shape]).
static func carve(carve_shape: CarveShape, prio: int, source: StringName) -> EmblemSpec:
	var e := EmblemSpec.new()
	e.register = Register.CARVE
	e.priority = prio
	e.shape = carve_shape
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
