extends GutTest

## Magic markers standalone: the arcane circle's two dashed rings turn at their
## own exported rates, its ghost stays still, the reticle-derived ghosts each
## hide one half of the reticle, and the magic theme maps every magic role.

const _DIR := "res://ui/indicator/"
const _ARCANE := _DIR + "arcane_circle.tscn"
const _ARCANE_GHOST := _DIR + "arcane_circle_ghost.tscn"
const _TARGET_GHOST := _DIR + "target_ghost.tscn"
const _FOOTPRINT := _DIR + "footprint_ring.tscn"
const _RETICLE := _DIR + "target_reticle.tscn"


func _make(path: String) -> Node2D:
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	assert_not_null(scene, "%s must exist" % path)
	if scene == null:
		return null
	var n := scene.instantiate() as Node2D
	add_child_autofree(n)
	n.set_process(false)
	return n


func test_arcane_rings_turn_at_their_own_rates_in_opposite_directions() -> void:
	var c := _make(_ARCANE)
	if c == null:
		return
	var outer := c.get_node("%Outer") as Node2D
	var inner := c.get_node("%Inner") as Node2D
	var outer_rate := float(c.get("outer_spin_deg_s"))
	var inner_rate := float(c.get("inner_spin_deg_s"))
	assert_lt(signf(outer_rate) * signf(inner_rate), 0.0, "default spins must be opposite")
	var o0 := outer.rotation
	var i0 := inner.rotation
	var dt := 0.25
	c.call("_process", dt)
	assert_almost_eq(outer.rotation - o0, deg_to_rad(outer_rate) * dt, 1e-5)
	assert_almost_eq(inner.rotation - i0, deg_to_rad(inner_rate) * dt, 1e-5)


func test_arcane_ghost_does_not_turn_and_hides_inner_ring() -> void:
	var g := _make(_ARCANE_GHOST)
	if g == null:
		return
	var outer := g.get_node("%Outer") as Node2D
	var before := outer.rotation
	g.call("_process", 0.5)
	assert_eq(outer.rotation, before)
	assert_true(outer.visible)
	assert_false((g.get_node("%Inner") as Node2D).visible)
	assert_eq(g.get("tier"), Emissive.Tier.INERT)


func test_dash_count_drawn_equals_export() -> void:
	var c := _make(_ARCANE)
	if c == null:
		return
	c.set("outer_dash_count", 12)
	c.set("inner_dash_count", 8)
	var outer := c.get_node("%Outer") as IndicatorDashedBand
	var inner := c.get_node("%Inner") as IndicatorDashedBand
	assert_eq(RangeRing.dash_spans(outer.fill, outer.dash_count).size(), 12)
	assert_eq(RangeRing.dash_spans(inner.fill, inner.dash_count).size(), 8)
	c.set("outer_dash_count", 5)
	assert_eq(RangeRing.dash_spans(outer.fill, outer.dash_count).size(), 5)


func test_target_ghost_hides_ring_and_keeps_arms() -> void:
	var g := _make(_TARGET_GHOST)
	if g == null:
		return
	assert_false((g.get_node("%Ring") as Node2D).visible)
	assert_true((g.get_node("%Spinner") as Node2D).visible)
	var spinner := g.get_node("%Spinner") as Node2D
	var before := spinner.rotation
	g.call("_process", 0.5)
	assert_eq(spinner.rotation, before)


func test_footprint_ring_hides_arms_and_keeps_ring() -> void:
	var f := _make(_FOOTPRINT)
	if f == null:
		return
	assert_true((f.get_node("%Ring") as Node2D).visible)
	assert_false((f.get_node("%Spinner") as Node2D).visible)
	assert_eq(f.get("tier"), Emissive.Tier.LABEL)


func test_target_ghost_desaturates_its_tint() -> void:
	var g := _make(_TARGET_GHOST)
	if g == null:
		return
	g.set("tint", Color(0.2, 1.0, 0.2, 1.0))
	var full := Emissive.at(Color(0.2, 1.0, 0.2, 1.0), Emissive.stops(Emissive.Tier.INERT))
	var spread_full := full.g - full.r
	var spread := g.modulate.g - g.modulate.r
	assert_lt(spread, spread_full, "ghost tint must be less saturated than the pushed tint")


func test_magic_theme_maps_every_magic_role() -> void:
	var t := load(_DIR + "themes/magic.tres") as IndicatorTheme
	var R := HighlightProvider.HighlightRole
	var want := {
		R.ORIGIN: _ARCANE, R.CASTER: _ARCANE_GHOST, R.IN_RANGE: _TARGET_GHOST,
		R.PROPAGATION: _FOOTPRINT, R.HOSTILE_TARGET: _RETICLE, R.FRIENDLY_TARGET: _RETICLE,
	}
	for role in want:
		var s := t.scene_for(role)
		assert_not_null(s, "magic.tres misses %s" % R.find_key(role))
		if s != null:
			assert_eq(s.resource_path, want[role])


func test_ranged_in_range_is_the_target_ghost() -> void:
	var t := load(_DIR + "themes/ranged.tres") as IndicatorTheme
	var s := t.scene_for(HighlightProvider.HighlightRole.IN_RANGE)
	assert_not_null(s)
	if s != null:
		assert_eq(s.resource_path, _TARGET_GHOST)
