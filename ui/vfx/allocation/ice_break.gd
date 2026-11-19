@tool
extends Node2D
## Ice-break shatter: a self-freeing one-shot where a Frozen node's ice broke
## ([signal Events.ice_shattered]). Shards burst from the node at once — no
## crescendo, unlike a node death — in an ice tint, and the burst grows with
## the break's excess, so a deep freeze visibly bursts bigger than a shallow
## one. Owns its own [ShatterField] and clock. Add it to its host FIRST, then
## [method play]. Every knob is tentative, easy to change.

## The shard colour; the field lifts it to [member spawn_tier].
@export var tint: Color = Color(0.62, 0.86, 1.0, 1.0)
## Emissive tier a shard is born at (a named stop, never a raw float).
@export var spawn_tier: Emissive.Tier = Emissive.Tier.ALERT
## Seconds a shard flies before it has faded out.
@export_range(0.05, 3.0, 0.01) var window: float = 0.6
## Shard disc radius = node radius × (base_scale + excess × scale_per_excess),
## capped at max_scale.
@export_range(0.1, 4.0, 0.05) var base_scale: float = 0.7
@export_range(0.0, 1.0, 0.01) var scale_per_excess: float = 0.12
@export_range(0.5, 8.0, 0.1) var max_scale: float = 2.5
## Shard count = base_shards + excess × shards_per_excess, capped by the field.
@export_range(1, 32, 1) var base_shards: int = 6
@export_range(0.0, 8.0, 0.1) var shards_per_excess: float = 1.5
## Radial kick (px/s) = base_kick + excess × kick_per_excess.
@export_range(0.0, 1000.0, 1.0) var base_kick: float = 60.0
@export_range(0.0, 200.0, 1.0) var kick_per_excess: float = 18.0

var _clock := 0.0


## The disc radius a break of [param excess] shatters at, on a node of
## [param node_radius].
func radius_for(node_radius: float, excess: int) -> float:
	return node_radius * minf(max_scale, base_scale + maxi(excess, 0) * scale_per_excess)


## Bursts at [param world_pos] for a node of [param node_radius] broken at
## [param excess]; frees itself when its shards have faded.
func play(world_pos: Vector2, node_radius: float, excess: int) -> void:
	global_position = world_pos
	var field := %Field as ShatterField
	field.window = window
	field.flight_start = 0.0
	field.spawn_tier = spawn_tier
	var e := maxi(excess, 0)
	field.spawn_shatter(Vector2.ZERO, radius_for(node_radius, e), tint, Vector2.ZERO, 0.0,
			base_shards + roundi(e * shards_per_excess), base_kick + e * kick_per_excess)
	_clock = 0.0
	set_process(true)
	var tween := create_tween()
	tween.tween_interval(window + 0.05)
	tween.tween_callback(queue_free)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_clock += delta
	(%Field as ShatterField).elapsed = _clock
