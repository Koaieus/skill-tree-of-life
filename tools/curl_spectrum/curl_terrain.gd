class_name CurlTerrain
extends RefCounted

## A bare piece of ground for [CurlOperator]: point positions plus an
## undirected, self-loop-free adjacency. Not a [Graph] — no scenes, no
## ownership, no stats — because a coefficient sweep builds hundreds of these
## and only the geometry and the topology can affect a curl.
##
## Built either from an idealised layout ([CurlLattices]) or from the real
## procgen pipeline ([CurlProcgenTerrain]).

var positions := PackedVector2Array()
## `adjacency[i]` = the point indices `i` is joined to, each listed once.
var adjacency: Array[PackedInt32Array] = []
## Free-text label used as the table's row name.
var label := ""


static func from_edges(label_: String, pts: PackedVector2Array, edges: Array) -> CurlTerrain:
	var t := CurlTerrain.new()
	t.label = label_
	t.positions = pts
	var sets: Array[Dictionary] = []
	for _i in pts.size():
		sets.append({})
	for e in edges:
		var a := int(e[0])
		var b := int(e[1])
		if a == b:
			continue  # a self-loop has no angular slot; Cyclone vetoes it anyway
		sets[a][b] = true
		sets[b][a] = true
	for i in pts.size():
		var row := PackedInt32Array()
		for k in sets[i].keys():
			row.append(int(k))
		row.sort()
		t.adjacency.append(row)
	return t


func edge_count() -> int:
	var total := 0
	for row in adjacency:
		total += row.size()
	return total / 2


func degree(i: int) -> int:
	return adjacency[i].size()


## The induced subgraph on the `size` points nearest `seed` in HOP distance —
## the stand-in for one entity's territory, grown the way allocation grows one
## (breadth-first out of a core). Ties inside the last ring are broken by index
## so a given (terrain, seed, size) is one fixed subgraph.
##
## Returns a terrain whose indices are its own; `mapping[i]` is the source
## index, for callers that need to point back at the parent.
func bfs_ball(seed_index: int, size: int) -> Dictionary:
	var order: Array[int] = [seed_index]
	var seen := {seed_index: true}
	var head := 0
	while head < order.size() and order.size() < size:
		var v: int = order[head]
		head += 1
		for nb in adjacency[v]:
			if order.size() >= size:
				break
			if seen.has(nb):
				continue
			seen[nb] = true
			order.append(nb)
	var remap := {}
	for i in order.size():
		remap[order[i]] = i
	var pts := PackedVector2Array()
	var edges: Array = []
	for i in order.size():
		pts.append(positions[order[i]])
		for nb in adjacency[order[i]]:
			if remap.has(nb) and int(remap[nb]) > i:
				edges.append([i, int(remap[nb])])
	return {
		"terrain": CurlTerrain.from_edges("%s/ball%d" % [label, size], pts, edges),
		"mapping": order,
	}
