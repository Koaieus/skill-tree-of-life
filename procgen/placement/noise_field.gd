@tool
class_name NoiseField
extends ScalarField

## Smooth wobbly bump map — a superposition-of-sines feel, not rough static.
## Wraps [FastNoiseLite] pinned to Simplex at low frequency/octaves by default
## (tune in the inspector) and remaps its [-1,1] output into [min_value,
## max_value].

@export var noise := FastNoiseLite.new()
@export var min_value: float = 0.5
@export var max_value: float = 1.5


func _init() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.01
	noise.fractal_octaves = 2


func sample(point: Vector2) -> float:
	var t := (noise.get_noise_2dv(point) + 1.0) * 0.5
	return lerpf(min_value, max_value, t)
