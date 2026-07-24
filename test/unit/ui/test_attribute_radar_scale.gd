extends GutTest

## AttributeRadar log-scale acceptance (#273, settled in issue comment
## "Swarmable spec — AttributeRadar scale (settled)"). D-18 makes INT a
## deliberate runaway (thousands) while CON/STR/DEX sit in the tens and WIS
## is bounded 100-200 -- three orders of magnitude on one polygon. The
## settled decision: STATIC log scale with a fixed floor/ceiling, and those
## bounds are SHARED across every entity (not per-entity dynamic) because the
## radar exists for cross-entity comparison (#228). log_floor/log_ceiling are
## placeholder tuning values (1 -> 10_000, see attribute_radar.gd) spanning
## the designed attribute range.


func _make_radar() -> AttributeRadar:
	var radar: AttributeRadar = preload("res://ui/gauges/attribute_radar.tscn").instantiate()
	add_child(radar)
	autofree(radar)
	return radar


func test_axes_plot_on_log_scale() -> void:
	var radar := _make_radar()
	await get_tree().process_frame

	# Doubling-and-doubling-again should NOT double the plotted fraction
	# (that would be linear) -- equal ratio steps should produce roughly
	# equal frac steps (log behavior).
	var f10: float = radar._value_frac(10.0)
	var f100: float = radar._value_frac(100.0)
	var f1000: float = radar._value_frac(1000.0)

	var step_a := f100 - f10
	var step_b := f1000 - f100
	assert_almost_eq(step_a, step_b, 0.01,
		"equal order-of-magnitude steps should produce ~equal frac steps under log scale")

	# And it must not be linear: 10 -> 1000 is a 100x jump but nowhere near
	# 100x the plotted fraction.
	assert_true(f1000 < f10 * 10.0, "log scale must compress large ratios, unlike a linear plot")


func test_floor_and_ceiling_are_fixed_and_shared_across_entities() -> void:
	var radar_a := _make_radar()
	var radar_b := _make_radar()
	await get_tree().process_frame

	# Same bounds by default (no per-entity override) -- this is the
	# load-bearing part of the settled decision (#228 cross-entity compare).
	assert_almost_eq(radar_a.log_floor, radar_b.log_floor, 0.0001)
	assert_almost_eq(radar_a.log_ceiling, radar_b.log_ceiling, 0.0001)

	# Two entities with very different attributes produce visibly different
	# plotted shapes -- assert the radii themselves differ, not just that
	# the calls succeed.
	radar_a.configure([AxisSpec.new("STR", Color.RED), AxisSpec.new("DEX", Color.GREEN), AxisSpec.new("INT", Color.BLUE)])
	radar_b.configure([AxisSpec.new("STR", Color.RED), AxisSpec.new("DEX", Color.GREEN), AxisSpec.new("INT", Color.BLUE)])
	radar_a.size = Vector2(150, 150)
	radar_b.size = Vector2(150, 150)

	# A low-level entity: tens across the board.
	radar_a.set_value(0, 10.0)
	radar_a.set_value(1, 12.0)
	radar_a.set_value(2, 15.0)

	# A high-level entity: INT runaway, three orders of magnitude above the
	# low-level entity's values.
	radar_b.set_value(0, 40.0)
	radar_b.set_value(1, 45.0)
	radar_b.set_value(2, 8000.0)

	for i in 3:
		var point_a: Vector2 = radar_a._axis_point(i, radar_a._value_frac(radar_a._values[i]))
		var point_b: Vector2 = radar_b._axis_point(i, radar_b._value_frac(radar_b._values[i]))
		var radius_a := point_a.distance_to(radar_a._get_center())
		var radius_b := point_b.distance_to(radar_b._get_center())
		assert_ne(radius_a, radius_b,
			"axis %d plotted radius must differ between two very different entities sharing the same scale" % i)


func test_three_orders_of_magnitude_yields_readable_web_no_degenerate_spike() -> void:
	var radar := _make_radar()
	await get_tree().process_frame
	radar.configure([AxisSpec.new("CON", Color.RED), AxisSpec.new("INT", Color.BLUE)])
	radar.size = Vector2(150, 150)

	radar.set_value(0, 29.0)     # CON-like, tens (D-18)
	radar.set_value(1, 8000.0)   # INT-like runaway, thousands (D-18)

	var frac_con: float = radar._value_frac(radar._values[0])
	var frac_int: float = radar._value_frac(radar._values[1])

	# No collapsed centre: the small value must still register above zero.
	assert_true(frac_con > 0.05, "a real attribute value must not collapse to the plot centre")
	# No degenerate spike: the huge value must not blow past the plot edge
	# or dwarf the small value into invisibility -- frac stays in [0, 1] and
	# the two remain visually distinguishable (not both pinned to ~1.0).
	assert_true(frac_int <= 1.0 and frac_int >= 0.0)
	assert_true(frac_int - frac_con > 0.05, "three orders of magnitude must still visibly separate the two axes")
	assert_true(frac_con - frac_int < 0.99, "the small value must not be squashed to indistinguishable from zero")


func test_value_at_or_below_floor_renders_at_floor_not_error() -> void:
	var radar := _make_radar()
	await get_tree().process_frame

	# At the floor exactly.
	var frac_floor: float = radar._value_frac(radar.log_floor)
	assert_almost_eq(frac_floor, 0.0, 0.0001, "a value at the floor should render at frac 0.0")

	# Below the floor -- still renders at the floor, no error, no -inf.
	var frac_below: float = radar._value_frac(radar.log_floor * 0.5)
	assert_almost_eq(frac_below, 0.0, 0.0001, "a value below the floor should clamp to the floor")
	assert_false(is_inf(frac_below))
	assert_false(is_nan(frac_below))

	# Negative value -- same clamp, no crash.
	var frac_negative: float = radar._value_frac(-500.0)
	assert_almost_eq(frac_negative, 0.0, 0.0001)
	assert_false(is_inf(frac_negative))
	assert_false(is_nan(frac_negative))


func test_value_zero_does_not_produce_negative_infinity() -> void:
	# log(0) is the obvious trap -- explicitly cover it.
	var radar := _make_radar()
	await get_tree().process_frame

	var frac: float = radar._value_frac(0.0)
	assert_false(is_inf(frac), "value 0 must not produce -inf")
	assert_false(is_nan(frac), "value 0 must not produce NaN")
	assert_almost_eq(frac, 0.0, 0.0001, "value 0 should render at the floor")

	# Make sure a full draw pass with a zero value doesn't error either.
	radar.configure([AxisSpec.new("A", Color.RED), AxisSpec.new("B", Color.BLUE), AxisSpec.new("C", Color.GREEN)])
	radar.set_value(0, 0.0)
	radar.size = Vector2(150, 150)
	radar.queue_redraw()
	await get_tree().process_frame
