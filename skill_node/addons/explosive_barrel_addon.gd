class_name ExplosiveBarrelAddon
extends SkillNodeAddon
## Explosive × Addon: the barrel. Not unique — barrels stack, and each is one
## explosive charge its carrier holds: at the owner's turn start an ALLOCATED
## carrier tops its charges up to the number of barrels it carries (flat,
## never stat-scaled — a count of explosions, not a magnitude), and a barrel
## leaving spends one charge if there is one. The blast's size is the node's
## own (the bomb is the node, [ExplosiveSpread]); a barrel carries no radius
## logic and no blade code — a swung piece's lives are its node's charges.
##
## Charge writes go through the carrier's status host: the refill lands as
## an apply of the deficit, the removal moves the row down by one.

## The charge this barrel refills — the Explosive aspect's status.
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
	var deficit := float(barrel_count()) - charges()
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
		if a is ExplosiveBarrelAddon and not a.is_temporary:
			n += 1
	return n


## This barrel's place among its carrier's barrels, in attach order; -1 once
## it has left. Barrel i draws charge segment i.
func barrel_index() -> int:
	if carrier == null:
		return -1
	var i := 0
	for a in carrier.get_addons():
		if a == self:
			return i
		if a is ExplosiveBarrelAddon:
			i += 1
	return -1


## The carrier's live explosive charges (0 without a combat slice, e.g. in
## the editor).
func charges() -> float:
	if charge_status == null or carrier == null or carrier.get_combat() == null:
		return 0.0
	return carrier.get_combat().get_status_power(charge_status.id)


func _on_carrier_changed() -> void:
	for child in get_children():
		if child is AddonVisual:
			child.queue_redraw()
