extends GutTest

## `graph/astar_skill_tree.gd:7-9` documents its own trap: `AStar2D`'s default
## heuristic is euclidean point distance, which wildly overestimates against
## unit edge costs and can silently return a non-fewest-hops path. This pins
## the exact failure shape.
##
## Fixture: a 2-hop path (S-A-G) that is geometrically LONG (~1414 units) vs a
## 4-hop "shortcut" (S-B-C-D-G) that sits almost exactly on the S-G line and
## totals only 1000 units. Hop-optimal picks the 2-hop path; a euclidean-cost
## regression (`_compute_cost`/`_estimate_cost` reverting to real distance)
## would prefer the shorter-but-longer-hop-count shortcut instead.

func test_returns_hop_optimal_path_not_the_euclidean_shortest() -> void:
	var astar := AStarSkillTree.new()

	var s := 0
	var a := 1
	var g := 2
	var b := 3
	var c := 4
	var d := 5

	astar.add_point(s, Vector2(0, 0))
	astar.add_point(a, Vector2(500, 500))
	astar.add_point(g, Vector2(1000, 0))
	astar.add_point(b, Vector2(250, 0))
	astar.add_point(c, Vector2(500, 0))
	astar.add_point(d, Vector2(750, 0))

	# 2-hop path: long in euclidean distance (~1414 total), short in hops.
	astar.connect_points(s, a)
	astar.connect_points(a, g)

	# 4-hop "shortcut": short in euclidean distance (1000 total), long in hops.
	astar.connect_points(s, b)
	astar.connect_points(b, c)
	astar.connect_points(c, d)
	astar.connect_points(d, g)

	var path := astar.get_id_path(s, g)
	assert_eq(path.size(), 3,
			"hop-optimal path is S-A-G (2 hops / 3 points), not the 4-hop shortcut")
	assert_eq(Array(path), [s, a, g])
