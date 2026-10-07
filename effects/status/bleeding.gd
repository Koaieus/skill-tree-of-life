class_name BleedingStatus
extends StatusDef

## Bleeding: an open wound. Each turn tick pays
## `round_half_up(stacks × bleed_rate)` flat HP on the PRE-decay row (`_on_tick`'s
## resisted `before`) through the shared [method DotTick.mint] — poison's door,
## so `damaged` / regen-suppression / a killing `notify_depleted` fire there.
## An exertion ([method StatusDef._on_exerted]: the node launched an attack, or
## the entity host's core moved) grows the RAW row by `× exert_growth`, rounded
## half-up once, and the host resets the ramp position; resting lets the
## authored [RampDecay] close it faster each turn. The projection is the NEXT
## tick only: the bar never guesses future exertion.

## Row multiplier per exertion. A tentative knob: ×2 until it proves OP.
@export_range(1.0, 4.0) var exert_growth: float = 2.0
## Flat HP paid per stack per tick, rounded half-up once on the product.
@export_range(0.0, 2.0) var bleed_rate: float = 0.5


func _on_tick(host, before: float, _after: float) -> void:
	DotTick.mint(host, _pay(before), HitInstance.AmountBasis.FLAT)


func _on_exerted(host) -> void:
	var power: float = host.get_status_power(id)
	var grow := round_half_up(power * (exert_growth - 1.0))
	if grow > 0.0:
		host.adjust_status_power(self, grow)


## One tick only: exertion growth is never projected.
func projected_damage(host, power: float) -> float:
	return next_tick_damage(host, power)


## What the next tick lands from a RAW row of [param power]: the host's
## resisted count × [member bleed_rate], rounded half-up — exactly [method _on_tick].
func next_tick_damage(host, power: float) -> float:
	return _pay(host.effective_status_power(self, power))


func _pay(stacks: float) -> float:
	return round_half_up(stacks * bleed_rate) if stacks > 0.0 else 0.0
