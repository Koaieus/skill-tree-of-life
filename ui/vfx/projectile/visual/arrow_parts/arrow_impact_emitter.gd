@tool
class_name ArrowImpactEmitter
extends ArrowEmitterPart

## A one-shot burst when the landing counts — the base burst. [member spread]
## picks where: at the arrowhead, around the target node's rim, or on every
## rider's target ([member ArrowImpactContext.rider_positions]; none = the
## arrowhead, a plain impact). Spread spots are emitted with
## [method GPUParticles2D.emit_particle] in world space, [member per_spot] each,
## so one emitter serves them all.

enum Spread {
	## At the arrowhead, where the arrow stuck.
	TIP,
	## [member rim_spots] points evenly round the target node's rim.
	RIM,
	## One spot per non-dud rider's target.
	RIDERS,
}

@export var spread: Spread = Spread.TIP
## Spots round the rim for [constant Spread.RIM].
@export_range(1, 32) var rim_spots: int = 6
## Particles per spot for a spread burst.
@export_range(1, 32) var per_spot: int = 4
## Seconds after the landing before the burst plays — a mark that lingers, then
## bursts. 0 = at the strike. Added to [method drain_seconds].
@export_range(0.0, 3.0, 0.05) var delay: float = 0.0

var _pending: int = 0


func arrive(ctx: ArrowImpactContext) -> void:
	if delay <= 0.0 or not is_inside_tree():
		_burst(ctx)
		return
	_pending += 1
	var ticket := _pending
	await get_tree().create_timer(delay).timeout
	if ticket == _pending:
		_burst(ctx)


func drain_seconds() -> float:
	return delay + super.drain_seconds()


## Cancels a burst still waiting out its [member delay].
func stop() -> void:
	_pending += 1


func _burst(ctx: ArrowImpactContext) -> void:
	var p := particles()
	if p == null:
		return
	var spots := spots_for(ctx)
	if spots.is_empty():
		p.restart()
		p.emitting = true
		return
	p.emitting = false
	var need := spots.size() * per_spot
	if p.amount < need:
		p.amount = need
	for spot in spots:
		for n in per_spot:
			p.emit_particle(Transform2D(0.0, spot), Vector2.ZERO, Color.WHITE, Color.WHITE,
					GPUParticles2D.EMIT_FLAG_POSITION)


## World positions a spread burst plays at; empty for a burst at the arrowhead.
func spots_for(ctx: ArrowImpactContext) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ctx == null:
		return out
	match spread:
		Spread.RIM:
			for k in rim_spots:
				var a := TAU * float(k) / float(rim_spots)
				out.append(ctx.position + Vector2(cos(a), sin(a)) * ctx.radius)
		Spread.RIDERS:
			out = ctx.rider_positions.duplicate()
	return out


func _sync_extra(p: GPUParticles2D) -> void:
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
