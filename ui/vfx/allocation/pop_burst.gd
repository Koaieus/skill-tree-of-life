@tool
extends Node2D
## Blade-pop burst: a sharp, short radial spray where a defender's spike pops an
## incoming blade vertex. The spray itself is authored on `%Particles` in the
## scene; this root maps spike power to a spawn radius and owns the lifetime.
## Add it to its host FIRST, then [method play].

## Seconds until the root frees itself; outlasts the particle lifetime.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.5
## Emission radius = min(max_radius, base_radius + power × radius_per_power).
@export_range(0.0, 64.0, 0.5) var base_radius: float = 6.0
@export_range(0.0, 16.0, 0.1) var radius_per_power: float = 2.0
@export_range(1.0, 128.0, 0.5) var max_radius: float = 22.0


## Sprays at [param world_pos] in [param color]; frees itself when done.
func play(world_pos: Vector2, spike_power: float, color: Color) -> void:
	global_position = world_pos
	var particles := %Particles as CPUParticles2D
	particles.color = color
	# The ramp is local to this instance (`resource_local_to_scene`), so the
	# recolour never leaks into another burst.
	var ramp := particles.color_ramp
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	# Spawned inside a disk, so the burst reads as a shatter, not a point.
	particles.emission_sphere_radius = maxf(1.0,
			minf(max_radius, base_radius + spike_power * radius_per_power))
	particles.emitting = true
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(queue_free)
