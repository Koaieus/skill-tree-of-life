extends GutTest
## AllocationVFX's transient effects are scenes, not code-composed trees: each
## loads and instantiates headless, the static spawners mount them, and every
## spawned root frees itself once its own clock runs out.
##
## Scenes are `load()`ed at runtime, never `preload()`ed: a missing path must
## fail an assert here, not turn the script into a silently skipped parse error.

const _DIR := "res://ui/vfx/allocation/"
const _DISK := _DIR + "snapshot_disk.tscn"
const _SPIKE := _DIR + "alloc_spike.tscn"
const _LIFT := _DIR + "dealloc_lift.tscn"
const _POP := _DIR + "pop_burst.tscn"


func _host() -> Node2D:
	var host := Node2D.new()
	add_child_autofree(host)
	host.position = Vector2(-120.0, 40.0)
	return host


func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for child in root.get_children():
		var hit := _find(child, pred)
		if hit != null:
			return hit
	return null


func test_each_effect_scene_loads_and_instantiates() -> void:
	for path in [_DISK, _SPIKE, _LIFT, _POP]:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "%s loads as a PackedScene" % path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		assert_true(inst is Node2D, "%s instantiates a Node2D root" % path)
		inst.free()


func test_static_spike_mounts_one_effect_holding_the_disk_scene_and_a_needle() -> void:
	var host := _host()
	AllocationVFX.spawn_alloc_spike(host, Vector2(300.0, -80.0), 12.0, 22.0, Color.RED)
	assert_eq(host.get_child_count(), 1, "exactly one effect root under the host")
	if host.get_child_count() != 1:
		return
	var effect := host.get_child(0)
	assert_eq(effect.scene_file_path, _SPIKE, "the root is the alloc-spike scene")
	assert_not_null(_find(effect, func(n: Node) -> bool: return n.scene_file_path == _DISK),
			"the spike carries the snapshot-disk scene")
	assert_not_null(_find(effect, func(n: Node) -> bool: return n is Polygon2D),
			"the needle is a Polygon2D")


func test_static_lift_mounts_one_effect_holding_the_disk_scene() -> void:
	var host := _host()
	AllocationVFX.spawn_dealloc_lift(host, Vector2(300.0, -80.0), 12.0, Color.RED)
	assert_eq(host.get_child_count(), 1, "exactly one effect root under the host")
	if host.get_child_count() != 1:
		return
	var effect := host.get_child(0)
	assert_eq(effect.scene_file_path, _LIFT, "the root is the dealloc-lift scene")
	assert_not_null(_find(effect, func(n: Node) -> bool: return n.scene_file_path == _DISK),
			"the lift carries the snapshot-disk scene")


func test_pop_burst_is_a_one_shot_24_particle_spray() -> void:
	var packed := load(_POP) as PackedScene
	assert_not_null(packed, "pop burst scene loads")
	if packed == null:
		return
	var burst := packed.instantiate()
	_host().add_child(burst)
	burst.play(Vector2(10.0, 10.0), 3.0, Color.CORNFLOWER_BLUE)
	var particles := _find(burst, func(n: Node) -> bool: return n is CPUParticles2D) as CPUParticles2D
	assert_not_null(particles, "the burst holds a CPUParticles2D")
	if particles == null:
		return
	assert_eq(particles.amount, 24, "24 particles")
	assert_true(particles.one_shot, "one-shot")
	assert_true(particles.emitting, "play() starts the emission")


## Each effect owns its clock: the root frees itself after its own durations,
## shortened here so the wait fits a unit-tier budget (the real spike lives 2.4 s).
func test_every_spawned_root_frees_itself_after_its_duration() -> void:
	var host := _host()
	var roots: Array[Node] = []
	for path in [_SPIKE, _LIFT, _POP]:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "%s loads" % path)
		if packed == null:
			return
		var inst := packed.instantiate()
		inst.set(&"duration", 0.05)
		if path == _SPIKE:
			inst.set(&"disk_linger", 0.05)
		host.add_child(inst)
		roots.append(inst)
	roots[0].play(Vector2.ZERO, 12.0, 22.0, Color.RED)
	roots[1].play(Vector2.ZERO, 12.0, Color.RED)
	roots[2].play(Vector2.ZERO, 3.0, Color.RED)
	await wait_seconds(0.6)
	for root in roots:
		assert_false(is_instance_valid(root), "a spawned effect frees itself")
