extends Node2D
## Blade/swing playground — GitHub #12 (standalone; unrelated to the game code).
##
## A phantom-blade sandbox. Build a small graph, pick a PIVOT (right-click a node)
## and a TARGET dummy (hover + T), then SPACE to swing. The blade is a free-pin
## verlet rig: the pivot is fixed, its first ring of bones is CLAMPED (welded to
## the swing frame), and every joint beyond that is a FREE PIN. Tensegrity is
## therefore emergent — triangles hold their shape, quads/chains flop into whips
## — straight out of the distance constraints, no rigidity stat anywhere.
##
## The target reports, per swing: which EDGES and which FACES (triangles/cycles)
## swept it, the contacting element's speed, that element's peak speed, and the
## resulting rest→rest ENVELOPE weight (= speed-at-contact / element-peak). The
## envelope is keyed off each element's OWN velocity, so a whip's late crack is
## credited at the crack — not clipped because the handle had already slowed.
##
## Controls
##   Left-click empty .... add node          Right-click node ... set PIVOT
##   Left-drag node→node . add edge          Hover + T .......... set TARGET
##   Shift+drag node ..... move node         Space .............. swing
##   1 / 2 / 3 ........... profile (sweep / crack / follow)
##   [ / ] ............... narrow / widen sector        R ... reset sample   C ... clear

const NODE_RADIUS := 9.0
const TARGET_RADIUS := 15.0
const HIT_PAD := 4.0
const SWING_DURATION := 0.75      # seconds, wall-clock
const ITER := 12                  # constraint relaxation iterations / step
const DAMPING := 0.992
const SPEED_REF := 1600.0         # px/s mapped to "hot" colour

enum Profile { SWEEP, CRACK, FOLLOW }

# ---- graph ----------------------------------------------------------------
var node_pos: Array = []          # Array[Vector2]
var edges: Array = []             # Array[[gi, gj]]
var pivot_idx := -1
var target_idx := -1
var theta := deg_to_rad(150.0)
var profile := Profile.SWEEP

# ---- blade (pivot's connected component, target excluded) -----------------
var blade: Array = []             # local -> global index
var local_of := {}                # global -> local
var blade_edges: Array = []       # [[la, lb], ...]
var triangles: Array = []         # [[la, lb, lc], ...]
var driven: Array = []            # bool per local (pivot + first ring = clamp)

# ---- physics --------------------------------------------------------------
var pts: Array = []               # Array[Vector2]
var prev: Array = []
var rest_off: Array = []          # rest offset from pivot, aim-rotated
var spd: Array = []               # px/s per local
var swinging := false
var swing_t := 0.0
var has_result := false
var trail: Array = []             # Array[Array[Vector2]] faded snapshots

# ---- contact bookkeeping --------------------------------------------------
var edge_contact := {}            # "la_lb" -> speed at first contact
var edge_peak := {}               # "la_lb" -> peak speed over swing
var tri_contact := {}             # "Tn"   -> speed at first contact
var tri_peak := {}                # "Tn"   -> peak speed
var report: Array = []            # Array[String]

# ---- interaction ----------------------------------------------------------
var hovered := -1
var drag_from := -1
var press_pos := Vector2.ZERO
var moving := false

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_reset_sample()


# ===========================================================================
#  GRAPH EDITING
# ===========================================================================
func _reset_sample() -> void:
	# triangle-on-a-stick (rigid head) extending into a 4-cycle (floppy) so both
	# behaviours are visible at once. Drag the target into the swing arc to taste.
	node_pos = [
		Vector2(240, 430),   # 0 pivot / handle
		Vector2(345, 372),   # 1 A  (stick tip)
		Vector2(432, 322),   # 2 B  -> rigid triangle 1-2-3
		Vector2(470, 405),   # 3 C
		Vector2(560, 286),   # 4 D  -> floppy quad 2-4-5-3
		Vector2(612, 372),   # 5 E
		Vector2(620, 210),   # 6 TARGET (dummy)
	]
	edges = [[0,1],[1,2],[1,3],[2,3],[2,4],[4,5],[5,3]]
	pivot_idx = 0
	target_idx = 6
	has_result = false
	_rebuild_blade()


func _clear() -> void:
	node_pos = []
	edges = []
	pivot_idx = -1
	target_idx = -1
	blade = []
	has_result = false
	_rebuild_blade()


func _node_at(p: Vector2) -> int:
	var best := -1
	var best_d := (NODE_RADIUS + 7.0)
	for i in node_pos.size():
		var d := p.distance_to(node_pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _has_edge(a: int, b: int) -> bool:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false


func _add_node(p: Vector2) -> void:
	node_pos.append(p)
	if pivot_idx < 0:
		pivot_idx = node_pos.size() - 1
	_rebuild_blade()


func _add_edge(a: int, b: int) -> void:
	if a != b and not _has_edge(a, b):
		edges.append([a, b])
		_rebuild_blade()


# ===========================================================================
#  BLADE EXTRACTION (BFS from pivot, target excluded)
# ===========================================================================
func _ek(a: int, b: int) -> String:
	return str(mini(a, b)) + "_" + str(maxi(a, b))


func _rebuild_blade() -> void:
	blade = []
	local_of = {}
	blade_edges = []
	triangles = []
	driven = []
	if pivot_idx < 0 or pivot_idx >= node_pos.size():
		return

	var adj := {}
	for i in node_pos.size():
		adj[i] = []
	for e in edges:
		if e[0] == target_idx or e[1] == target_idx:
			continue
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])

	var seen := {pivot_idx: true}
	var q := [pivot_idx]
	while not q.is_empty():
		var n: int = q.pop_front()
		blade.append(n)
		for m in adj[n]:
			if not seen.has(m):
				seen[m] = true
				q.append(m)
	for l in blade.size():
		local_of[blade[l]] = l

	for e in edges:
		if local_of.has(e[0]) and local_of.has(e[1]):
			blade_edges.append([local_of[e[0]], local_of[e[1]]])

	driven.resize(blade.size())
	for l in blade.size():
		driven[l] = false
	var lp: int = local_of[pivot_idx]
	driven[lp] = true                       # pivot fixed
	for be in blade_edges:                   # first ring = clamped grip
		if be[0] == lp:
			driven[be[1]] = true
		elif be[1] == lp:
			driven[be[0]] = true

	# triangles = faces (the common, meaningful case)
	var eset := {}
	for be in blade_edges:
		eset[_ek(be[0], be[1])] = true
	var n := blade.size()
	for a in n:
		for b in range(a + 1, n):
			if not eset.has(_ek(a, b)):
				continue
			for c in range(b + 1, n):
				if eset.has(_ek(a, c)) and eset.has(_ek(b, c)):
					triangles.append([a, b, c])


# ===========================================================================
#  SWING
# ===========================================================================
func _profile_ease(t: float) -> float:
	match profile:
		Profile.CRACK:                       # slow load, violent late snap
			return t * t * t
		Profile.FOLLOW:                      # fast start, long settle
			return 1.0 - pow(1.0 - t, 3.0)
		_:                                   # SWEEP: smoothstep, peak in the middle
			return t * t * (3.0 - 2.0 * t)


func _profile_name() -> String:
	match profile:
		Profile.CRACK: return "crack"
		Profile.FOLLOW: return "follow"
		_: return "sweep"


func _start_swing() -> void:
	_rebuild_blade()
	if blade.size() < 2:
		return
	var pv: Vector2 = node_pos[pivot_idx]

	# aim: rotate the rest shape so its centroid points at the target, so the
	# sweep is centred on the target and actually crosses it mid-stroke.
	var rot := 0.0
	if target_idx >= 0:
		var cen := Vector2.ZERO
		for gi in blade:
			cen += node_pos[gi]
		cen /= blade.size()
		var fwd := cen - pv
		var aim: Vector2 = node_pos[target_idx] - pv
		if fwd.length() > 1.0 and aim.length() > 1.0:
			rot = aim.angle() - fwd.angle()

	pts.resize(blade.size())
	prev.resize(blade.size())
	rest_off.resize(blade.size())
	spd.resize(blade.size())
	var phi0 := -theta / 2.0
	for l in blade.size():
		rest_off[l] = (node_pos[blade[l]] - pv).rotated(rot)
		var p: Vector2 = pv + rest_off[l].rotated(phi0)
		pts[l] = p
		prev[l] = p
		spd[l] = 0.0

	swing_t = 0.0
	swinging = true
	has_result = false
	edge_contact.clear(); edge_peak.clear()
	tri_contact.clear(); tri_peak.clear()
	trail.clear()


func _physics_process(delta: float) -> void:
	if not swinging:
		return
	swing_t += delta / SWING_DURATION
	var done := swing_t >= 1.0
	swing_t = minf(swing_t, 1.0)
	var phi := -theta / 2.0 + _profile_ease(swing_t) * theta
	var pv: Vector2 = node_pos[pivot_idx]

	# 1. drive clamped nodes kinematically; integrate free nodes (verlet)
	for l in blade.size():
		if driven[l]:
			var old: Vector2 = pts[l]
			prev[l] = old
			pts[l] = pv + rest_off[l].rotated(phi)
		else:
			var temp: Vector2 = pts[l]
			pts[l] = pts[l] + (pts[l] - prev[l]) * DAMPING
			prev[l] = temp

	# 2. relax rigid bones (free angle => tensegrity emerges)
	for _it in ITER:
		for be in blade_edges:
			_satisfy(be[0], be[1])

	# 3. per-element speed (this is the damage envelope's input)
	for l in blade.size():
		spd[l] = (pts[l] - prev[l]).length() / delta

	_check_contacts()
	if Engine.get_physics_frames() % 2 == 0:
		trail.append(pts.duplicate())

	if done:
		swinging = false
		has_result = true
		_finalize()
	queue_redraw()


func _satisfy(a: int, b: int) -> void:
	var rest_len: float = (rest_off[a] - rest_off[b]).length()
	var d: Vector2 = pts[b] - pts[a]
	var dist := d.length()
	if dist < 0.0001:
		return
	var diff := (dist - rest_len) / dist
	var wa := 0.0 if driven[a] else 1.0
	var wb := 0.0 if driven[b] else 1.0
	var w := wa + wb
	if w == 0.0:
		return
	pts[a] += d * diff * (wa / w)
	pts[b] -= d * diff * (wb / w)


func _check_contacts() -> void:
	if target_idx < 0:
		return
	var T: Vector2 = node_pos[target_idx]
	for be in blade_edges:
		var a: Vector2 = pts[be[0]]
		var b: Vector2 = pts[be[1]]
		var es: float = (spd[be[0]] + spd[be[1]]) * 0.5
		var key := str(be[0]) + "_" + str(be[1])
		edge_peak[key] = maxf(edge_peak.get(key, 0.0), es)
		if not edge_contact.has(key) and _seg_point_dist(a, b, T) <= TARGET_RADIUS + HIT_PAD:
			edge_contact[key] = es
	for ti in triangles.size():
		var t = triangles[ti]
		var es: float = (spd[t[0]] + spd[t[1]] + spd[t[2]]) / 3.0
		var key := "T" + str(ti)
		tri_peak[key] = maxf(tri_peak.get(key, 0.0), es)
		if not tri_contact.has(key) and _point_in_tri(T, pts[t[0]], pts[t[1]], pts[t[2]]):
			tri_contact[key] = es


func _finalize() -> void:
	report = []
	var V := blade.size()
	var E := blade_edges.size()
	var cyc := E - V + 1
	report.append("BLADE  V=%d  E=%d  cycles=%d  triangles=%d" % [V, E, cyc, triangles.size()])
	var laman := E >= 2 * V - 3
	report.append("tensegrity: %s" % ("braced — rigid-capable" if laman else "under-braced — floppy / whip"))
	report.append("profile=%s   sector=%d deg" % [_profile_name(), int(rad_to_deg(theta))])
	if target_idx < 0:
		report.append("(no target: hover a node and press T)")
		return

	var any := false
	var total := 0.0
	for be in blade_edges:
		var key := str(be[0]) + "_" + str(be[1])
		if edge_contact.has(key):
			any = true
			var cs: float = edge_contact[key]
			var pk: float = maxf(edge_peak.get(key, cs), 0.001)
			var w := clampf(cs / pk, 0.0, 1.0)
			var dmg := 10.0 * w
			total += dmg
			var tag := "  [face edge]" if _edge_in_triangle(be) else ""
			report.append("  edge %d-%d  v=%.0f  peak=%.0f  envelope=%.2f  dmg~%.1f%s"
				% [blade[be[0]], blade[be[1]], cs, pk, w, dmg, tag])
	for ti in triangles.size():
		var key := "T" + str(ti)
		if tri_contact.has(key):
			any = true
			var cs: float = tri_contact[key]
			var pk: float = maxf(tri_peak.get(key, cs), 0.001)
			var w := clampf(cs / pk, 0.0, 1.0)
			var dmg := 20.0 * w
			total += dmg
			var t = triangles[ti]
			report.append("  FACE %d-%d-%d  envelope=%.2f  dmg~%.1f"
				% [blade[t[0]], blade[t[1]], blade[t[2]], w, dmg])
	if not any:
		report.append("  MISS — nothing swept the target (drag it into the arc)")
	else:
		report.append("  TOTAL ~ %.1f   (illustrative numbers)" % total)


func _edge_in_triangle(be: Array) -> bool:
	for t in triangles:
		var s := {t[0]: true, t[1]: true, t[2]: true}
		if s.has(be[0]) and s.has(be[1]):
			return true
	return false


# ---- geometry helpers -----------------------------------------------------
func _seg_point_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign2(p, a, b)
	var d2 := _sign2(p, b, c)
	var d3 := _sign2(p, c, a)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)


func _sign2(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)


# ===========================================================================
#  INPUT
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = _node_at(event.position)
		if moving and drag_from >= 0:
			node_pos[drag_from] = event.position
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			press_pos = event.position
			drag_from = _node_at(event.position)
			moving = drag_from >= 0 and event.shift_pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var n := _node_at(event.position)
			if n >= 0 and n != target_idx:
				pivot_idx = n
				has_result = false
				_rebuild_blade()
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var n := _node_at(event.position)
		if moving:
			pass
		elif drag_from >= 0 and n >= 0 and n != drag_from:
			_add_edge(drag_from, n)
		elif drag_from < 0 and event.position.distance_to(press_pos) < 6.0:
			_add_node(event.position)
		drag_from = -1
		moving = false
		has_result = false
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _start_swing()
			KEY_T:
				if hovered >= 0:
					target_idx = hovered
					if pivot_idx == target_idx:
						pivot_idx = -1
					has_result = false
					_rebuild_blade()
			KEY_R: _reset_sample()
			KEY_C: _clear()
			KEY_1: profile = Profile.SWEEP
			KEY_2: profile = Profile.CRACK
			KEY_3: profile = Profile.FOLLOW
			KEY_BRACKETLEFT: theta = maxf(deg_to_rad(20.0), theta - deg_to_rad(10.0))
			KEY_BRACKETRIGHT: theta = minf(deg_to_rad(330.0), theta + deg_to_rad(10.0))
		queue_redraw()


# ===========================================================================
#  DRAW
# ===========================================================================
func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.09, 0.10, 0.13))

	_draw_arc_guide()

	# rest graph (faint when a phantom is on screen)
	var rest_a := 0.35 if (swinging or has_result) else 1.0
	for e in edges:
		var hot: bool = e[0] == target_idx or e[1] == target_idx
		if hot:
			continue
		draw_line(node_pos[e[0]], node_pos[e[1]], Color(0.45, 0.5, 0.6, rest_a), 2.0)
	for i in node_pos.size():
		_draw_node(i, rest_a)

	# trail
	for s in trail.size():
		var snap = trail[s]
		var a := 0.04 + 0.10 * (float(s) / maxf(trail.size(), 1))
		for be in blade_edges:
			draw_line(snap[be[0]], snap[be[1]], Color(0.55, 0.8, 1.0, a), 1.5)

	# live / resulting phantom blade
	if swinging or has_result:
		_draw_faces()
		for be in blade_edges:
			var s := 0.0
			if spd.size():
				s = (spd[be[0]] + spd[be[1]]) * 0.5
			var c := Color(0.35, 0.55, 0.9).lerp(Color(1.0, 0.85, 0.25), clampf(s / SPEED_REF, 0.0, 1.0))
			draw_line(pts[be[0]], pts[be[1]], c, 3.0)
		for l in blade.size():
			var col := Color(0.95, 0.75, 0.2) if driven[l] else Color(0.55, 0.75, 1.0)
			draw_circle(pts[l], NODE_RADIUS - 2.0, col)

	_draw_report()
	_draw_help()


func _draw_arc_guide() -> void:
	if pivot_idx < 0 or target_idx < 0:
		return
	var pv: Vector2 = node_pos[pivot_idx]
	var aim: float = (node_pos[target_idx] - pv).angle()
	var r := pv.distance_to(node_pos[target_idx]) + 30.0
	draw_arc(pv, r, aim - theta / 2.0, aim + theta / 2.0, 48, Color(1, 1, 1, 0.10), 2.0)
	draw_line(pv, pv + Vector2.from_angle(aim - theta / 2.0) * r, Color(1, 1, 1, 0.08), 1.0)
	draw_line(pv, pv + Vector2.from_angle(aim + theta / 2.0) * r, Color(1, 1, 1, 0.08), 1.0)


func _draw_faces() -> void:
	for ti in triangles.size():
		var t = triangles[ti]
		var poly := PackedVector2Array([pts[t[0]], pts[t[1]], pts[t[2]]])
		var hit := tri_contact.has("T" + str(ti))
		var col := Color(1.0, 0.6, 0.3, 0.20) if hit else Color(0.5, 0.7, 1.0, 0.08)
		draw_colored_polygon(poly, col)


func _draw_node(i: int, alpha: float) -> void:
	var p: Vector2 = node_pos[i]
	var col := Color(0.6, 0.7, 0.85, alpha)
	if i == target_idx:
		col = Color(0.95, 0.3, 0.3, 1.0)
		draw_arc(p, TARGET_RADIUS, 0, TAU, 32, Color(1, 0.4, 0.4, 0.9), 2.0)
	elif i == pivot_idx:
		col = Color(0.95, 0.75, 0.2, alpha)
	if i == hovered:
		draw_arc(p, NODE_RADIUS + 4.0, 0, TAU, 24, Color(1, 1, 1, 0.7), 1.5)
	draw_circle(p, NODE_RADIUS, col)
	draw_string(_font, p + Vector2(11, -10), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1, 1, 1, 0.5 * alpha + 0.3))


func _draw_report() -> void:
	var lines: Array = []
	if has_result:
		lines = report
	else:
		lines = [
			"BLADE  V=%d  E=%d  triangles=%d" % [blade.size(), blade_edges.size(), triangles.size()],
			"profile=%s   sector=%d deg" % [_profile_name(), int(rad_to_deg(theta))],
			"press SPACE to swing",
		]
	var y := 24.0
	draw_string(_font, Vector2(18, y), "— TARGET REPORT —", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.9, 0.95, 1.0))
	y += 22.0
	for ln in lines:
		draw_string(_font, Vector2(18, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.95))
		y += 19.0


func _draw_help() -> void:
	var vp := get_viewport_rect().size
	var help := "L-click empty: node   L-drag node→node: edge   Shift-drag: move   "
	help += "R-click: pivot   hover+T: target   Space: swing   1/2/3 profile   [ ] sector   R reset   C clear"
	draw_string(_font, Vector2(18, vp.y - 16), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.65, 0.7, 0.8))
