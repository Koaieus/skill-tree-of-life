@tool
extends Node2D
## "Skill point from the heavens": a white-hot needle drops onto the node and
## sinks back in, over a snapshot disk that flashes and lingers. Spawned by
## [method AllocationVFX.spawn_alloc_spike]; add it to its host FIRST, then
## [method play] — `global_position` out of the tree silently writes `position`.
##
## The root sets its own absolute z (`ZLayers.SPELL_VFX`), so it wins over
## fog-promoted nodes from any parent chain. The inspector values of
## `inner_radius` / `node_radius` are a preview only; [method play] overwrites them.

const ZLayers = preload("res://ui/z_layers.gd")

@export_range(0.05, 2.0, 0.01) var duration: float = 0.4
## Needle height = node radius × this.
@export_range(1.0, 12.0, 0.1) var height_factor: float = 6.0:
	set(value):
		height_factor = value
		_rebuild()
## Lorentzian profile w(t) ∝ γ² / (γ² + t²), tip pinned to 0. Smaller γ →
## narrower needle, sharper shoulders. ~0.22 reads as a clean resonance peak;
## toward 0.5 a candle flame, below 0.15 a hair-thin spire.
@export_range(0.05, 1.0, 0.01) var needle_gamma: float = 0.22:
	set(value):
		needle_gamma = value
		_rebuild()
## Per side; total polygon verts = 2 × samples + 1.
@export_range(2, 64) var samples: int = 14:
	set(value):
		samples = value
		_rebuild()
## How long the disk takes to fade once the needle is gone.
@export_range(0.05, 5.0, 0.05) var disk_linger: float = 2.0
## Needle half-width at the base and the disk radius (the inner fill circle).
@export var inner_radius: float = 12.0:
	set(value):
		inner_radius = value
		_rebuild()
@export var node_radius: float = 22.0:
	set(value):
		node_radius = value
		_rebuild()

## Share of [member duration] the needle spends growing before it sinks.
const _SCALE_RAMPUP_FRAC := 0.5


func _init() -> void:
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX


func _ready() -> void:
	_rebuild()


## Starts the effect at [param world_pos] in [param color]; frees itself when done.
func play(world_pos: Vector2, inner_r: float, node_r: float, color: Color) -> void:
	global_position = world_pos
	inner_radius = inner_r
	node_radius = node_r
	var disk := %Disk
	var needle := %Needle as Polygon2D
	disk.disk_color = color
	# Polygon2D.color is the draw tint — alpha multiplies with modulate.a, so it
	# stays opaque and visibility rides modulate.a only.
	needle.color = color
	disk.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)
	needle.modulate = Emissive.at(Color.WHITE, Emissive.PEAK)

	# Bound to this instance: the effect owns its clock, so a static caller
	# needs no node of its own to hang it off.
	var tween := create_tween()
	tween.set_parallel(true)
	# Alpha 0.5 → 1 (the disk's own fade below takes it out).
	modulate.a = 0.5
	tween.tween_property(self, "modulate:a", 1.0, duration * 0.2)
	# Height 0 → 1 → 0. The base sits at y=0, so scaling y → 0 sinks it in.
	needle.scale.y = 0.0
	tween.tween_property(needle, "scale:y", 1.0, duration * _SCALE_RAMPUP_FRAC)
	tween.tween_property(needle, "scale:y", 0.0, duration * (1.0 - _SCALE_RAMPUP_FRAC))\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)\
			.set_delay(duration * _SCALE_RAMPUP_FRAC)
	tween.tween_property(disk, "modulate:a", 0.0, disk_linger)\
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)\
			.set_delay(duration)
	tween.chain().tween_callback(queue_free)


func _rebuild() -> void:
	if not is_node_ready():
		return
	%Disk.disk_radius = inner_radius
	(%Needle as Polygon2D).polygon = build_needle_polygon(
			inner_radius, node_radius * height_factor, needle_gamma, samples)


## Lorentzian (Breit-Wigner-ish) needle profile. Base at y=0 with full width
## `2 * half_w`; tip pinned to (0, -height). Wound right base → tip → left
## base; y points DOWN, so "up" is negative y.
static func build_needle_polygon(half_w: float, height: float, gamma: float,
		sample_count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var gamma_sq := gamma * gamma
	# Right side, t=0 → just below the tip; the tip is appended explicitly so
	# its width is exactly 0.
	for i in sample_count:
		var t := float(i) / float(sample_count)
		# (1 - t^6) eases the last samples into the pinned tip without a kink.
		var w := half_w * gamma_sq / (gamma_sq + t * t) * (1.0 - pow(t, 6.0))
		pts.append(Vector2(w, -t * height))
	pts.append(Vector2(0.0, -height))
	for i in range(sample_count - 1, -1, -1):
		var t := float(i) / float(sample_count)
		var w := half_w * gamma_sq / (gamma_sq + t * t) * (1.0 - pow(t, 6.0))
		pts.append(Vector2(-w, -t * height))
	return pts
