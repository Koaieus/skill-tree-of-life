@tool
class_name CampAnnulusStarters
extends StarterPlacement

## Places every contender on the level's outer annulus, in a shape driven off
## the roster's camp structure (#551). Three arrangements, two geometries:
## GROUPED clusters each camp into a narrow arc (allies a couple hops apart,
## rivals on opposite rims); ALTERNATING and RANDOM place `N = sum(camp_sizes)`
## uniform slots at `2π/N` and differ only in assignment order.
##
## GROUPED is not an optimisation over "minimise same-camp distance, maximise
## cross-camp distance" — on a disc the closed form dominates a search, and
## ALTERNATING is the deliberate OPPOSITE of that framing. All three are
## wanted; the host picks one.

enum Arrangement { GROUPED, ALTERNATING, RANDOM }

@export var arrangement: Arrangement = Arrangement.GROUPED
## Anchor radius as a fraction of the resolved mask radius.
@export_range(0.0, 1.0) var annulus_fraction: float = 0.85
## GROUPED only: the arc (radians) a camp's members are packed along. Widened
## at runtime — never authored down — if it would pack members closer than
## the clamp in [method _effective_arc_span]; see that method's docstring.
@export var camp_arc_span: float = 0.21

## Margin over `min_dist` the GROUPED arc clamp enforces. Deliberately not
## 1.0: clamping exactly to `min_dist` would put every clamped configuration
## on the floating-point boundary of the very rejection test
## ([PoissonDiskSampler]'s `_grid_ok`) that silently drops a crowded anchor.
const _ARC_CLAMP_MARGIN := 1.5


func plan(
		camp_sizes: Array[int],
		radius: float,
		min_dist: float,
		rng: RandomNumberGenerator,
) -> Array[StartingPoint]:
	var out: Array[StartingPoint] = []
	var total := 0
	for n in camp_sizes:
		total += maxi(0, n)
	if total <= 0:
		push_warning("CampAnnulusStarters: camp_sizes is empty/all-zero — no starters placed")
		return out

	# Drawn exactly once, first — every arrangement's geometry is anchored
	# off it, and RANDOM's shuffle (the only other rng consumer) always comes
	# after it, so `plan` is deterministic for a given seed + camp shape.
	var theta0 := rng.randf() * TAU
	var r := annulus_fraction * radius

	match arrangement:
		Arrangement.GROUPED:
			out = _plan_grouped(camp_sizes, r, theta0, min_dist)
		Arrangement.ALTERNATING:
			out = _plan_alternating(camp_sizes, r, theta0)
		Arrangement.RANDOM:
			out = _plan_random(camp_sizes, r, theta0, rng)
	return out


# ── GROUPED ────────────────────────────────────────────────────────────────


func _plan_grouped(
		camp_sizes: Array[int], r: float, theta0: float, min_dist: float,
) -> Array[StartingPoint]:
	var out: Array[StartingPoint] = []
	var c_count := camp_sizes.size()
	for c in c_count:
		var n: int = camp_sizes[c]
		if n <= 0:
			continue
		var theta_c := theta0 + TAU * float(c) / float(c_count)
		var span := _effective_arc_span(n, r, min_dist)
		for m in n:
			var theta := theta_c if n == 1 else theta_c + span * (float(m) / float(n - 1) - 0.5)
			out.append(_make_point(theta, r, c, m))
	return out


## Widens [member camp_arc_span] for THIS camp (never mutates the export —
## camp sizes are a runtime input, so this can't be an authoring-time
## warning) until adjacent members clear `_ARC_CLAMP_MARGIN * min_dist`. A
## single member has no adjacent spacing to protect, so it's exempt.
func _effective_arc_span(n: int, r: float, min_dist: float) -> float:
	if n <= 1 or r <= 0.0:
		return camp_arc_span
	var target_chord := _ARC_CLAMP_MARGIN * min_dist
	# Chord between two points on a circle of radius r, angular_step apart:
	# chord = 2r·sin(step/2). Solve for the step that hits target_chord,
	# clamping the asin argument to 1 (max chord on this circle is 2r — a
	# target beyond that can only ask for the largest step available, PI).
	var half_chord_ratio := clampf(target_chord / (2.0 * r), 0.0, 1.0)
	var required_step := 2.0 * asin(half_chord_ratio)
	var required_span := required_step * float(n - 1)
	return maxf(camp_arc_span, required_span)


# ── ALTERNATING ───────────────────────────────────────────────────────────


func _plan_alternating(camp_sizes: Array[int], r: float, theta0: float) -> Array[StartingPoint]:
	var c_count := camp_sizes.size()
	var total := 0
	for n in camp_sizes:
		total += maxi(0, n)

	# Round-robin fill order: which camp claims slot i, skipping camps whose
	# members are already exhausted (unequal camp sizes degrade gracefully).
	var remaining := camp_sizes.duplicate()
	var slot_camp := PackedInt32Array()
	slot_camp.resize(total)
	var cursor := 0
	for i in total:
		while remaining[cursor] <= 0:
			cursor = (cursor + 1) % c_count
		slot_camp[i] = cursor
		remaining[cursor] -= 1
		cursor = (cursor + 1) % c_count

	# Invert: for each (camp, member) pair, which slot did the round-robin
	# above give it? Needed because the return contract is participant order,
	# not slot order.
	var next_member := PackedInt32Array()
	next_member.resize(c_count)
	var slot_of_member: Array[PackedInt32Array] = []
	for c in c_count:
		var arr := PackedInt32Array()
		arr.resize(maxi(0, camp_sizes[c]))
		slot_of_member.append(arr)
	for i in total:
		var c: int = slot_camp[i]
		var m: int = next_member[c]
		next_member[c] = m + 1
		slot_of_member[c][m] = i

	var out: Array[StartingPoint] = []
	for c in c_count:
		var n: int = camp_sizes[c]
		for m in n:
			var slot_idx: int = slot_of_member[c][m]
			var theta := theta0 + TAU * float(slot_idx) / float(total)
			out.append(_make_point(theta, r, c, m))
	return out


# ── RANDOM ────────────────────────────────────────────────────────────────


func _plan_random(
		camp_sizes: Array[int], r: float, theta0: float, rng: RandomNumberGenerator,
) -> Array[StartingPoint]:
	var participants: Array[Vector2i] = []  # (camp, member)
	for c in camp_sizes.size():
		for m in camp_sizes[c]:
			participants.append(Vector2i(c, m))
	var total := participants.size()

	# Fisher-Yates over the slot each participant lands in — never
	# Array.shuffle() (.claude/rules/multiplayer-sync.md): a versus peer
	# reproduces this map from the seed rather than receiving it.
	var slot_of := range(total)
	for i in range(total - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: int = slot_of[i]
		slot_of[i] = slot_of[j]
		slot_of[j] = tmp

	var out: Array[StartingPoint] = []
	for i in total:
		var p := participants[i]
		var theta := theta0 + TAU * float(slot_of[i]) / float(total)
		out.append(_make_point(theta, r, p.x, p.y))
	return out


func _make_point(theta: float, r: float, camp: int, member: int) -> StartingPoint:
	var sp := StartingPoint.new()
	sp.position = Vector2(cos(theta), sin(theta)) * r
	sp.id = StringName("camp_%d_member_%d" % [camp, member])
	return sp
