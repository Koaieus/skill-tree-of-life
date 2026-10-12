extends GutTest

## [CrucibleTraces.route]: each filled socket's trace runs down, then right,
## into its readout line, and no two traces cross (acceptance 2 of #1585).
## Pair 0 leaves the rightmost socket and feeds the topmost line.

const STEP := 8.0
const GAP := 10.0
const ANCHOR_X := 400.0


## Socket pads along a downward arc like [InfusionSockets]', pair 0 rightmost;
## readout anchors stacked top to bottom on a common left edge, above the turns.
func _case(n: int) -> Array[PackedVector2Array]:
	var froms := PackedVector2Array()
	var tos := PackedVector2Array()
	var half := deg_to_rad(100.0) * 0.5 if n > 1 else 0.0
	for k in n:
		var theta := lerpf(half, -half, float(k) / (n - 1)) if n > 1 else 0.0
		froms.append(Vector2(120.0 + 90.0 * sin(theta), 150.0 + 90.0 * (cos(theta) - cos(half))))
		tos.append(Vector2(ANCHOR_X, 60.0 + 18.0 * k))
	return [froms, tos]


static func _crosses(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for i in a.size() - 1:
		for j in b.size() - 1:
			if Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1]) != null:
				return true
	return false


func test_no_two_traces_cross_for_one_two_and_three_sockets() -> void:
	for n in [1, 2, 3]:
		var c := _case(n)
		var traces := CrucibleTraces.route(c[0], c[1], STEP, GAP)
		assert_eq(traces.size(), n, "%d sockets, %d traces" % [n, n])
		for i in traces.size():
			for j in range(i + 1, traces.size()):
				assert_false(_crosses(traces[i], traces[j]),
						"%d sockets: traces %d and %d cross: %s / %s" % [n, i, j, traces[i], traces[j]])


func test_each_trace_leaves_its_socket_downward_and_ends_on_its_line_from_the_left() -> void:
	var c := _case(3)
	var traces := CrucibleTraces.route(c[0], c[1], STEP, GAP)
	assert_eq(traces.size(), 3)
	for k in traces.size():
		var t := traces[k]
		assert_gt(t.size(), 2, "trace %d bends" % k)
		if t.size() < 3:
			continue
		assert_eq(t[0], c[0][k], "trace %d starts on its socket" % k)
		assert_eq(t[t.size() - 1], c[1][k], "trace %d ends on its line's anchor" % k)
		assert_almost_eq(t[1].x, t[0].x, 0.01, "trace %d first runs straight down" % k)
		assert_gt(t[1].y, t[0].y, "trace %d first runs down" % k)
		assert_almost_eq(t[2].y, t[1].y, 0.01, "then turns right")
		assert_gt(t[2].x, t[1].x, "then turns right")
		assert_lt(t[t.size() - 2].x, t[t.size() - 1].x, "and enters its line from the left")


## The rightmost socket turns first; each next one turns [code]turn_step[/code] lower.
func test_turns_step_down_from_the_rightmost_socket() -> void:
	var c := _case(3)
	var traces := CrucibleTraces.route(c[0], c[1], STEP, GAP)
	assert_eq(traces.size(), 3)
	for k in range(1, traces.size()):
		assert_almost_eq(traces[k][1].y - traces[k - 1][1].y, STEP, 0.01, "turn %d sits one step lower" % k)
