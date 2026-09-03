extends GutTest

## EuclideanRangeFinder — straight-line reach. in_range() is the
## single-candidate predicate; gather() is the one-traversal distance-set
## sibling (.claude/rules/graph.md: use gather(), never in_range() in a loop).

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _source: SkillNode
var _inside: SkillNode
var _on_boundary: SkillNode
var _just_outside: SkillNode
var _finder: EuclideanRangeFinder


func before_each() -> void:
	_source = _NODE_SCENE.instantiate() as SkillNode
	_inside = _NODE_SCENE.instantiate() as SkillNode
	_on_boundary = _NODE_SCENE.instantiate() as SkillNode
	_just_outside = _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(_source)
	add_child_autofree(_inside)
	add_child_autofree(_on_boundary)
	add_child_autofree(_just_outside)

	_source.position = Vector2.ZERO
	_inside.position = Vector2(50, 0)
	_on_boundary.position = Vector2(100, 0)
	_just_outside.position = Vector2(101, 0)

	_finder = EuclideanRangeFinder.new()
	_finder.max_distance = 100.0


func test_in_range_accepts_inside_and_boundary() -> void:
	assert_true(_finder.in_range(null, _source, _inside))
	assert_true(_finder.in_range(null, _source, _on_boundary))


func test_in_range_rejects_just_outside() -> void:
	assert_false(_finder.in_range(null, _source, _just_outside))


func test_gather_returns_known_reachable_set_including_the_source() -> void:
	var mirror := GraphMirror.new()
	autofree(mirror)
	mirror.mirror_add(_source)
	mirror.mirror_add(_inside)
	mirror.mirror_add(_on_boundary)
	mirror.mirror_add(_just_outside)

	var result := _finder.gather(_source, mirror)

	assert_true(result.has(_source))
	assert_almost_eq(result[_source], 0.0, 0.001)
	assert_true(result.has(_inside))
	assert_almost_eq(result[_inside], 50.0, 0.001)
	assert_true(result.has(_on_boundary))
	assert_almost_eq(result[_on_boundary], 100.0, 0.001)
	assert_false(result.has(_just_outside),
			"a node just past max_distance must not appear in the gathered set")


func test_max_reach_reports_max_distance() -> void:
	assert_almost_eq(_finder.max_reach(), 100.0, 0.001)


## #727 split `spell_range` from `spell_hops`; euclidean reach keeps scaling
## by `spell_range`, via SpellRangeRules.multiplier's board-preview tier. Board
## built and set in-code (owner's standing rule): the shipped INT rate is
## explicitly due for post-LAN retuning, so a golden pinned to it would be red
## by design — this only pins that the multiplier is still consumed at all.
func test_effective_distance_still_scales_by_spell_range() -> void:
	var board: EntityStatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_range"
	mod.operation = StatModifier.Operation.SET
	mod.value = 50.0
	board.add_modifier(mod)

	var scaled := _finder.effective_distance(null, null, board)

	assert_almost_eq(scaled, _finder.max_distance * 1.5, 0.001,
			"+50%% spell_range must scale euclidean reach by 1.5x, unaffected by the #727 split")


func test_effective_distance_with_no_board_or_attacker_is_unscaled() -> void:
	assert_almost_eq(_finder.effective_distance(null, null, null), _finder.max_distance, 0.001)
