@tool
class_name CatalystBarrelAddon
extends SkillNodeAddon
## Catalyst × Addon: the barrel. Not unique — barrels stack, and each is one
## stack of the Catalyst status its carrier holds: at the owner's turn start
## an ALLOCATED carrier tops its Catalyst up to the number of barrels it
## carries (flat, never stat-scaled), and a barrel leaving takes one stack
## off if there is one. Catalyst only converts what lands on its node and
## never goes off; a barrel carries no radius or blast logic and no blade
## code.
##
## Writes go through the carrier's status host: the refill lands as an apply
## of the deficit, the removal moves the row down by one.
##
## A temp barrel is the same addon for one swing: no refill, no removal
## spend, and the carrier's row is never written — it adds nothing to a swing.

## The status this barrel refills — the Catalyst aspect's.
@export var charge_status: StatusDef = null


func _ready() -> void:
	super()
	if carrier != null:
		carrier.statuses_changed.connect(_on_carrier_changed)
		carrier.addons_changed.connect(_on_carrier_changed)


func _exit_tree() -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	if carrier.statuses_changed.is_connected(_on_carrier_changed):
		carrier.statuses_changed.disconnect(_on_carrier_changed)
	if carrier.addons_changed.is_connected(_on_carrier_changed):
		carrier.addons_changed.disconnect(_on_carrier_changed)


func on_turn_start() -> void:
	if charge_status == null or carrier == null or not carrier.is_allocated():
		return
	var deficit := float(barrel_count()) - stacks()
	if deficit > 0.0:
		carrier.get_combat().apply_status(charge_status, deficit)


func on_detached() -> void:
	if charge_status == null or carrier == null or carrier.is_queued_for_deletion():
		return
	carrier.get_combat().adjust_status_power(charge_status, -1.0)


## Non-temporary barrels currently on the carrier — the refill target.
func barrel_count() -> int:
	if carrier == null:
		return 0
	var n := 0
	for a in carrier.get_addons():
		if a is CatalystBarrelAddon and not a.is_temporary:
			n += 1
	return n


## This barrel's place among its carrier's barrels, in attach order; -1 once
## it has left. Barrel i draws crystal i.
func barrel_index() -> int:
	if carrier == null:
		return -1
	var i := 0
	for a in carrier.get_addons():
		if a == self:
			return i
		if a is CatalystBarrelAddon:
			i += 1
	return -1


## The carrier's live Catalyst stacks (0 without a combat slice, e.g. in
## the editor).
func stacks() -> float:
	if charge_status == null or carrier == null or carrier.get_combat() == null:
		return 0.0
	return carrier.get_combat().get_status_power(charge_status.id)


func _on_carrier_changed() -> void:
	for child in get_children():
		if child is AddonVisual:
			child.queue_redraw()
