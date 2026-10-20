@tool
class_name AspectIntake
extends Resource

## One row of a spell's intake list: the spell carries [member innate] of
## [member identity]'s concept, and ingests an infusion of it at its
## **affinity** `affinity_gain:affinity_cost` (0 refuses it), on top of the
## spell-wide ingest rate. The **load** is
## `innate + floor(infusion × ingest × affinity)` — see [method Infusion.load_of]
## and the glossary in docs/domain/aspect-cell-authoring.md § Infusion. The load
## lands per hit through the concept status's own [method StatusDef.stacks_per_hit]
## fold. Points at the concept's [Identity], never an [Aspect] (an Aspect lists
## its spells: an edge back would be a resource cycle) nor a [StatusDef] (a
## concept need not have one); the status resolves by concept id
## ([method status]).

## The concept this row takes in — the Aspect's identity, keyed by its id.
@export var identity: Identity = null:
	set(value):
		identity = value
		emit_changed()
## The load the spell carries with no infusion spent.
@export_range(0, 100, 1, "or_greater") var innate: int = 0:
	set(value):
		innate = maxi(value, 0)
		emit_changed()
## Affinity numerator: load gained per [member affinity_cost] infused; 0 refuses.
@export_range(0, 10, 1, "or_greater") var affinity_gain: int = 1:
	set(value):
		affinity_gain = maxi(value, 0)
		emit_changed()
## Affinity denominator: infusion spent per [member affinity_gain] load; ≥ 1.
@export_range(1, 10, 1, "or_greater") var affinity_cost: int = 1:
	set(value):
		affinity_cost = maxi(value, 1)
		emit_changed()
## Extra-stack terms the PLANT rider of this row carries ([member
## ApplyStatusEffect.stack_terms]), each a [StackTerm] read at land against the
## landing world. A spell that also scales its damage by the same term shares
## the SubResource with its [AddStackTermDamageEffect]: one formula, two readers.
@export var stack_terms: Array[StackTerm] = []:
	set(value):
		stack_terms = value
		emit_changed()
## The PLANT rider's [member ApplyStatusEffect.power_from]: the id of a
## [CarriedScalar] whose value it lands instead of the load, where the payload
## carries one. Empty = the load at every landing.
@export var power_from: StringName = &"":
	set(value):
		power_from = value
		emit_changed()
## How a hit spends this row's load — the row's **face**:
## DETONATE: spent at the hit as a blast ([DetonateEffect]); PLANT: lands as
## the concept's status rider at `power = load`; FUEL: no rider, the load only
## shapes the spell — a spread reads it from [member PropagationContext.load]
## (Firecracker's explosive fuel). INHERIT takes the concept's
## [member StatusDef.default_face] ([method resolved_face]).
enum Face { INHERIT, DETONATE, PLANT, FUEL }

## This row's face; INHERIT (the default) defers to the concept's status.
@export var face: Face = Face.INHERIT:
	set(value):
		face = value
		emit_changed()

## The concept id this row keys on (`&"poison"`); `&""` unset.
func aspect_id() -> StringName:
	return identity.id if identity != null else &""


## The status this concept's load lands as, by concept id; null if it has none.
func status() -> StatusDef:
	var id := aspect_id()
	return null if id.is_empty() else StatusRoster.shared().by_concept(id)


## [member face], INHERIT resolved through the concept status's
## [member StatusDef.default_face] — PLANT when the concept has no status.
func resolved_face() -> Face:
	if face != Face.INHERIT:
		return face
	return face_of_status(status())


## The face a row left INHERIT takes for [param def]: its authored
## [member StatusDef.default_face], PLANT when [param def] is null.
static func face_of_status(def: StatusDef) -> Face:
	if def != null and def.default_face == Face.DETONATE:
		return Face.DETONATE
	return Face.PLANT


## True iff this row's affinity is 0 — the spell takes no infusion of it.
func refuses() -> bool:
	return affinity_gain <= 0


## The on-arrival line: [method StatusDef.applies_line] of the innate load —
## the fold the landing itself uses, so a [param board] carrying the attacker's
## `<family>_stacks_per_hit` scales it here exactly as it scales the rider —
## with the row's affinity as its suffix. A [param read_node] folds through its
## live slice instead, as the rider lands.
func get_description(board: StatBoard = null, read_node: SkillNode = null) -> String:
	var def := status()
	if def == null:
		return "Applies nothing (no status set)."
	var name := def.display_name if not def.display_name.is_empty() else String(def.id)
	var concept := name.to_lower()
	var ingest := "refuses %s infusions" % concept if refuses() \
			else "+%s per %s infused" % [NumFmt.num(float(affinity_gain) / affinity_cost), concept]
	return def.applies_line(board, float(innate), "; " + ingest, OnHitEffect.read_slice(read_node))
