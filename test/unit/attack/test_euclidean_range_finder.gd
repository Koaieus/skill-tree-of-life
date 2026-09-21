extends GutTest

## EuclideanRangeFinder — straight-line reach. in_range() is the
## single-candidate predicate; gather() is the one-traversal distance-set
## sibling (.claude/rules/graph.md: use gather(), never in_range() in a loop).
##
## Reach rule (#944, owner): "any part of the candidate's hitbox" — a
## candidate is in range when `d - candidate.radius <= reach`, the source
## measured from its centre. The fixture nodes are the stock skill_node.tscn
## (radius 32) at reach 100, so the rim boundary sits at d = 132.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _source: SkillNode
var _inside: SkillNode
var _on_boundary: SkillNode
var _hitbox_touching: SkillNode
var _just_outside: SkillNode
var _finder: EuclideanRangeFinder


func before_each() -> void:
	_source = _NODE_SCENE.instantiate() as SkillNode
	_inside = _NODE_SCENE.instantiate() as SkillNode
	_on_boundary = _NODE_SCENE.instantiate() as SkillNode
	_hitbox_touching = _NODE_SCENE.instantiate() as SkillNode
	_just_outside = _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(_source)
	add_child_autofree(_inside)
	add_child_autofree(_on_boundary)
	add_child_autofree(_hitbox_touching)
	add_child_autofree(_just_outside)

	_finder = EuclideanRangeFinder.new()
	_finder.max_distance = 100.0

	var reach := _finder.max_distance
	var r := _inside.radius
	_source.position = Vector2.ZERO
	_inside.position = Vector2(50, 0)
	# Centre exactly on the reach circle: in under both the old centre rule and
	# the hitbox rule.
	_on_boundary.position = Vector2(reach, 0)
	# Centre past the circle, but half its hitbox overlaps it: in under the
	# hitbox rule only (#944 acceptance 1).
	_hitbox_touching.position = Vector2(reach + r * 0.5, 0)
	# One pixel past the rim boundary: out under both rules.
	_just_outside.position = Vector2(reach + r + 1.0, 0)


func _mirror_of_all() -> GraphMirror:
	var mirror := GraphMirror.new()
	autofree(mirror)
	mirror.mirror_add(_source)
	mirror.mirror_add(_inside)
	mirror.mirror_add(_on_boundary)
	mirror.mirror_add(_hitbox_touching)
	mirror.mirror_add(_just_outside)
	return mirror


func test_in_range_accepts_inside_and_boundary() -> void:
	assert_true(_finder.in_range(null, _source, _inside))
	assert_true(_finder.in_range(null, _source, _on_boundary))


func test_in_range_rejects_just_outside() -> void:
	assert_false(_finder.in_range(null, _source, _just_outside))


func test_in_range_accepts_a_candidate_whose_hitbox_overlaps_the_reach_circle() -> void:
	assert_true(_finder.in_range(null, _source, _hitbox_touching),
			"centre at reach + radius/2: part of the hitbox is inside the circle")


func test_in_range_accepts_a_candidate_whose_rim_exactly_touches_the_reach_circle() -> void:
	_hitbox_touching.position = Vector2(_finder.max_distance + _hitbox_touching.radius, 0)
	assert_true(_finder.in_range(null, _source, _hitbox_touching),
			"d - radius == reach is the inclusive boundary")


func test_source_is_measured_from_its_centre_not_its_rim() -> void:
	_source.base_radius = 96.0
	assert_false(_finder.in_range(null, _source, _just_outside),
			"a fat source must not reach further: only the candidate's radius counts")
	var result := _finder.gather(_source, _mirror_of_all())
	assert_false(result.has(_just_outside))
	var multi := _finder.gather_multi([_source], _mirror_of_all())
	assert_false(multi[_source].has(_just_outside))


func test_gather_returns_known_reachable_set_including_the_source() -> void:
	var result := _finder.gather(_source, _mirror_of_all())

	assert_true(result.has(_source))
	assert_almost_eq(result[_source], 0.0, 0.001)
	assert_true(result.has(_inside))
	assert_almost_eq(result[_inside], 50.0, 0.001)
	assert_true(result.has(_on_boundary))
	assert_almost_eq(result[_on_boundary], 100.0, 0.001)
	assert_true(result.has(_hitbox_touching),
			"hitbox overlapping the circle is in range (#944)")
	assert_almost_eq(result[_hitbox_touching], 116.0, 0.001,
			"the stored distance stays centre-to-centre: it feeds DistanceScale")
	assert_false(result.has(_just_outside),
			"a node whose whole hitbox is past reach must not appear in the gathered set")


func test_gather_multi_applies_the_same_hitbox_rule_per_source() -> void:
	var far_source := _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(far_source)
	# A second source whose reach circle contains nothing but itself.
	far_source.position = Vector2(0, 1000)
	var mirror := _mirror_of_all()
	mirror.mirror_add(far_source)

	var multi := _finder.gather_multi([_source, far_source], mirror)

	var near: Dictionary = multi[_source]
	assert_true(near.has(_hitbox_touching),
			"gather_multi must not lose the hitbox-touching candidate to its widest-reach reject")
	assert_almost_eq(near[_hitbox_touching], 116.0, 0.001)
	assert_true(near.has(_on_boundary))
	assert_false(near.has(_just_outside))
	var far: Dictionary = multi[far_source]
	assert_true(far.has(far_source))
	assert_eq(far.size(), 1, "the far source reaches nothing else")


func test_max_reach_reports_max_distance() -> void:
	assert_almost_eq(_finder.max_reach(), 100.0, 0.001)


## Euclidean reach is the authored `max_distance` folded as the base under
## `cast_range_distance`, via SpellRangeRules.reach's board-preview tier. Board
## hand-built with no intrinsics (owner's standing rule): the shipped INT rate
## is the owner's to tune, so this only pins that the stat is consumed at all.
func test_effective_distance_scales_by_a_cast_range_distance_increase() -> void:
	var board := EntityStatBoard.new()
	var s := ScalarStat.new()
	s.definition = StatRegistry.get_def(&"cast_range_distance")
	s.base_value = 0.0
	board.set(&"cast_range_distance", s)
	var mod := StatModifier.new()
	mod.stat_id = &"cast_range_distance"
	mod.operation = StatModifier.Operation.INCREASE
	mod.value = 50.0
	board.add_modifier(mod)

	var scaled := _finder.effective_distance(null, null, board)

	assert_almost_eq(scaled, _finder.max_distance * 1.5, 0.001,
			"+50%% increased cast_range_distance must scale euclidean reach by 1.5x")


func test_effective_distance_with_no_board_or_attacker_is_unscaled() -> void:
	assert_almost_eq(_finder.effective_distance(null, null, null), _finder.max_distance, 0.001)
