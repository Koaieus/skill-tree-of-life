class_name CurlLattices
extends RefCounted

## The idealised terrains #703 tuned Cyclone against, as [CurlTerrain]s — the
## calibration column every #705 sweep is read next to, and the acceptance gate
## for [CurlOperator] itself (`test/unit/spell/test_curl_spectrum.gd`).
##
## These are hand-drawn ground: a lone ring, a wheel, a triangulated patch.
## Real procgen ground is Poisson-disk + Delaunay + a pruned share of the
## extras, which is a different distribution entirely — that is the whole
## reason #705 exists. Keep both tables side by side and never quote one for
## the other.

## Points closer together than this share an edge in the lattice builders. The
## lattices are laid out at unit spacing, so anything under the √3 next-nearest
## distance separates a real edge from a diagonal.
const _LATTICE_EPSILON := 1.2


## Every pair within [constant _LATTICE_EPSILON] — the triangulation of a
## regular point set, without asking Delaunay for it.
static func near_neighbour_edges(pts: PackedVector2Array) -> Array:
	var edges: Array = []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if pts[i].distance_to(pts[j]) <= _LATTICE_EPSILON:
				edges.append([i, j])
	return edges


static func path(n: int) -> CurlTerrain:
	var pts := PackedVector2Array()
	var edges: Array = []
	for i in n:
		pts.append(Vector2(float(i), 0.0))
		if i > 0:
			edges.append([i - 1, i])
	return CurlTerrain.from_edges("path-%d" % n, pts, edges)


static func star(leaves: int) -> CurlTerrain:
	var pts := PackedVector2Array([Vector2.ZERO])
	var edges: Array = []
	for i in leaves:
		var a := TAU * float(i) / float(leaves)
		pts.append(Vector2(cos(a), sin(a)))
		edges.append([0, i + 1])
	return CurlTerrain.from_edges("star-%d" % leaves, pts, edges)


## A binary tree of `depth` levels, splayed so no two children coincide.
static func binary_tree(depth: int) -> CurlTerrain:
	var pts := PackedVector2Array([Vector2.ZERO])
	var edges: Array = []
	var frontier: Array[int] = [0]
	for level in range(1, depth):
		var next: Array[int] = []
		var count := frontier.size() * 2
		for k in count:
			var a := TAU * float(k) / float(count)
			pts.append(Vector2(cos(a), sin(a)) * float(level))
			var child := pts.size() - 1
			edges.append([frontier[k / 2], child])
			next.append(child)
		frontier = next
	return CurlTerrain.from_edges("binary-tree-%d" % depth, pts, edges)


static func ring(n: int) -> CurlTerrain:
	var pts := PackedVector2Array()
	var edges: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)))
		edges.append([i, (i + 1) % n])
	return CurlTerrain.from_edges("ring-%d" % n, pts, edges)


## A ring with a long tail hanging off it — the "stringy chain with one loop"
## row: everything the tail contributes decays, so ρ is the ring's alone.
static func ring_with_tail(n: int, tail: int) -> CurlTerrain:
	var pts := PackedVector2Array()
	var edges: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)))
		edges.append([i, (i + 1) % n])
	var previous := 0
	for t in tail:
		pts.append(Vector2(2.0 + float(t), 0.0))
		edges.append([previous, pts.size() - 1])
		previous = pts.size() - 1
	return CurlTerrain.from_edges("ring-%d+tail-%d" % [n, tail], pts, edges)


## Two triangles sharing an edge.
static func double_triangle() -> CurlTerrain:
	var h := sqrt(3.0) * 0.5
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, h), Vector2(0.5, -h),
	])
	return CurlTerrain.from_edges("double-triangle", pts, near_neighbour_edges(pts))


## Hub plus a ring of `spokes`, every spoke joined to the hub and to its two
## ring neighbours.
static func wheel(spokes: int) -> CurlTerrain:
	var pts := PackedVector2Array([Vector2.ZERO])
	var edges: Array = []
	for i in spokes:
		var a := TAU * float(i) / float(spokes)
		pts.append(Vector2(cos(a), sin(a)))
		edges.append([0, i + 1])
		edges.append([i + 1, 1 + (i + 1) % spokes])
	return CurlTerrain.from_edges("wheel-%d" % spokes, pts, edges)


## A hexagonal patch of the triangular lattice: `rings` shells around a centre,
## so 1 / 7 / 19 / 37 / 61 points.
static func triangular_lattice(rings: int) -> CurlTerrain:
	var basis_a := Vector2(1.0, 0.0)
	var basis_b := Vector2(0.5, sqrt(3.0) * 0.5)
	var pts := PackedVector2Array()
	for q in range(-rings, rings + 1):
		for r in range(-rings, rings + 1):
			if absi(q + r) > rings:
				continue
			pts.append(basis_a * float(q) + basis_b * float(r))
	return CurlTerrain.from_edges(
			"tri-lattice-%d" % pts.size(), pts, near_neighbour_edges(pts))


## Every idealised terrain the #705 table calibrates against, in table order.
static func calibration_set() -> Array[CurlTerrain]:
	return [
		path(6),
		star(5),
		binary_tree(4),
		ring(3), ring(4), ring(5), ring(6),
		ring_with_tail(4, 5),
		double_triangle(),
		wheel(6),
		triangular_lattice(2),
		triangular_lattice(3),
	]
