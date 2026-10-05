@tool
class_name Aspect
extends Resource

## One concept's row of the aspect matrix as data (`docs/design/aspect_matrix.md`):
## the facets one concept is expressed through — its count stat, its status,
## its arrow, its addon, its spells. Authored as `aspects/defs/<concept>.tres`
## and listed on [AspectRoster].
##
## Facets point at the [Identity], never at the Aspect — this resource is the
## only edge from a concept to its facets, so there is no cycle. Every facet
## that carries an identity carries THIS one (`test_aspect_roster.gd` pins it).
## A facet whose cell has not landed is null (or an empty array); the cell that
## lands it sets it here (`docs/domain/aspect-cell-authoring.md`).

## The concept — name, tint, icon. [method id] reads through it.
@export var identity: Identity = null
## The `<concept>_aspect` count stat, a child of the `aspects` family parent.
@export var stat: StatDef = null
## The concept's status. Null for a concept with none (explosive).
@export var status: StatusDef = null
## The concept's special arrow. Null until its arrow cell lands.
@export var ammo: AmmoType = null
## The concept's [SkillNodeAddon] scene (map and temp are one scene). Null
## until its addon cell lands.
@export var addon_scene: PackedScene = null
## Spells expressing the concept — any status one applies is this concept's.
@export var spells: Array[SpellDef] = []


func id() -> StringName:
	return identity.id if identity != null else &""
