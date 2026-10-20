@tool
class_name MidasMarkAddon
extends SkillNodeAddon
## Greed × Addon: Midas Mark. On the map it grants its owner Greed aspect and,
## at the owner's turn start, tops its ALLOCATED carrier's own Greed up by
## [method gain] toward [method cap] — never past it, so the bait refills as
## hits spend it and never grows unbounded (Greed never decays). Both scale
## with the carrier's allocation level. On a blade it is the plain Greed rider
## (authored on the scene); a temporary copy never runs the turn-start hook.
##
## The top-up lands as an apply of the deficit through the carrier's status
## host (Greed accumulates), so it settles and notifies like any landing.

## The status this mark grows on its carrier — Greed.
@export var greed_status: StatusDef = null
## Greed gained per turn start, flat part. Tentative knob.
@export_range(0, 10, 1) var gain_flat: int = 0
## Greed gained per turn start, per allocation level. Tentative knob.
@export_range(0, 10, 1) var gain_per_level: int = 1
## The top-up ceiling, per allocation level. Tentative knob.
@export_range(0, 20, 1) var cap_per_level: int = 3


func on_turn_start() -> void:
	if greed_status == null or carrier == null or not carrier.is_allocated():
		return
	var top_up := minf(float(gain()), float(cap()) - greed())
	if top_up > 0.0:
		carrier.get_combat().apply_status(greed_status, top_up)


## Greed this mark adds per turn start at the carrier's allocation level.
func gain() -> int:
	return gain_flat + gain_per_level * _level()


## The Greed count the mark tops its carrier up to, never past.
func cap() -> int:
	return cap_per_level * _level()


## The carrier's current Greed.
func greed() -> float:
	if greed_status == null or carrier == null or carrier.get_combat() == null:
		return 0.0
	return carrier.get_combat().get_status_power(greed_status.id)


func _level() -> int:
	return carrier.allocation_level if carrier != null else 0
