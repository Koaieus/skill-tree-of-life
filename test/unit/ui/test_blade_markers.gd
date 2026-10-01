extends GutTest

## Melee indicator members standalone: the hilt's guard lies across its
## facing; blade members share one ripple clock offset by order; the threat
## marker and the candidate ghost hold their exported tiers.

const _HILT := "res://ui/indicator/hilt_marker.tscn"
const _MEMBER := "res://ui/indicator/blade_member_marker.tscn"
const _GHOST := "res://ui/indicator/blade_member_ghost.tscn"
const _THREAT := "res://ui/indicator/threat_marker.tscn"


func _make(path: String) -> Node2D:
	var scene := load(path) as PackedScene
	assert_not_null(scene, "%s must exist" % path)
	if scene == null:
		return null
	var m := scene.instantiate() as Node2D
	add_child_autofree(m)
	return m


func _peak_time(m: Node2D) -> float:
	# Sample the brightness function over one period at 1 ms resolution.
	var period: float = m.get("period_s")
	var best_t := 0.0
	var best := -INF
	var t := 0.0
	while t < period:
		var v: float = m.call("brightness_at", t)
		if v > best:
			best = v
			best_t = t
		t += 0.001
	return best_t


func test_hilt_guard_lies_across_facing() -> void:
	var h := _make(_HILT)
	if h == null:
		return
	var facing := Vector2(0.6, 0.8)
	h.set("facing", facing)
	var guard := h.get_node("%Guard") as Node2D
	assert_almost_eq(guard.rotation, facing.angle() + PI / 2.0, 0.0001)


func test_members_peak_order_steps_apart() -> void:
	var a := _make(_MEMBER)
	var b := _make(_MEMBER)
	if a == null or b == null:
		return
	a.set("order", 1)
	b.set("order", 4)
	var step: float = a.get("ripple_step_s")
	var period: float = a.get("period_s")
	var dt := fposmod(_peak_time(b) - _peak_time(a), period)
	assert_almost_eq(dt, 3.0 * step, 0.002)


func test_ghost_is_static_and_inert() -> void:
	var g := _make(_GHOST)
	if g == null:
		return
	assert_eq(g.get("tier"), Emissive.Tier.INERT)
	assert_eq(g.call("brightness_at", 0.0), g.call("brightness_at", 0.37))


func test_threat_tier_is_the_exported_one() -> void:
	var t := _make(_THREAT)
	if t == null:
		return
	assert_eq(t.get("tier"), Emissive.Tier.LABEL)
	t.set("tier", Emissive.Tier.ALERT)
	assert_eq(t.get("tier"), Emissive.Tier.ALERT)
