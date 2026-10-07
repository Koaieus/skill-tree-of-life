@tool
class_name ArrowShedEmitter
extends ArrowEmitterPart

## Particles left along the flight — the base trail, poison's froth. Emits
## from launch until the strike (or a dud), never again after.
## [member density] thins emission through [member GPUParticles2D.amount_ratio]
## so a 20-arrow volley stays readable instead of carpeting the board.

## Share of [member amount] actually emitted (0 = none).
@export_range(0.0, 1.0, 0.01) var density: float = 1.0:
	set(v):
		density = v
		_sync()
## World space leaves particles where they were shed; local drags them along.
@export var world_space: bool = true:
	set(v):
		world_space = v
		_sync()

var _stopped: bool = false


func _init() -> void:
	show_on_dud = true
	show_on_absorbed = true


func launch() -> void:
	var p := particles()
	if p != null and not _stopped:
		p.emitting = true


func stop() -> void:
	_stopped = true
	var p := particles()
	if p != null:
		p.emitting = false


func _sync_extra(p: GPUParticles2D) -> void:
	p.amount_ratio = density
	p.local_coords = not world_space
