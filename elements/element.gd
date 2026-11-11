@tool
class_name Element
extends Resource

## One element as data (`docs/domain/elements.md`): a second axis beside
## [Aspect] — one count stat and a family of member statuses with fixed roles
## (the terrain stack, the movers) plus the ordered bands its terrain stack
## primes into. Authored as `elements/defs/<element>.tres` and listed on
## [ElementRoster]. The fields it shares with [Aspect] keep [Aspect]'s names;
## an element is not a parent of aspects and an aspect is not a member.

## The element — name, tint, icon ([code]Kind.ELEMENT[/code]). [method id] reads through it.
@export var identity: Identity = null
## The `<element>_element` count stat: its COUNT facet, no family parent.
@export var stat: StatDef = null
## The one terrain stack (Heat, Cold, Charge) — side-less, read per node.
@export var terrain: StatusDef = null
## The element's sided movers (Frostbite joins Ice with #1444). Empty in v1.
@export var movers: Array[StatusDef] = []
## The attribute whose pool rolls this count ([code]Kind.ATTRIBUTE[/code]).
@export var school: Identity = null
## The element's arrow. Null until its arrow cell lands (#1810).
@export var ammo: AmmoType = null
## The element's [SkillNodeAddon] scene. Null until its addon cell lands (#1804).
@export var addon_scene: PackedScene = null
## Spells expressing the element. Empty until its spell cells land.
@export var spells: Array[SpellDef] = []
## Terrain decay per world turn below the first band (a knob; read by #1795).
@export_range(0, 100, 1, "or_greater") var decay_per_world_turn: int = 1
## The bands the terrain stack primes into, ascending. Nothing stores a band:
## #1794's band function reads this list against (count, T, k).
@export var bands: Array[ElementBand] = []


func id() -> StringName:
	return identity.id if identity != null else &""
