extends GutTest

## SkillNode's authored-vs-derived size split: `base_radius` / `base_inner_radius`
## are the exported knobs, `radius` / `inner_radius` are read-only getters over
## them plus stake growth.
##
## The split exists because SkillNode is `@tool`. The previous design wrote
## stake growth back into an exported `radius`, so opening a staked node's scene
## in the editor serialized the GROWN radius into the `.tscn` and the next load
## grew it again from there — compounding on every save. These tests pin the
## properties that make that impossible.

const SkillNodeScene := preload("res://skill_node/skill_node.tscn")


func _make() -> SkillNode:
	var sn: SkillNode = SkillNodeScene.instantiate()
	add_child_autofree(sn)
	return sn


func test_stake_growth_table() -> void:
	# stake 1 is the ~99% case and must add nothing; each level adds one delta.
	var sn := _make()
	var expected := [32.0, 38.0, 44.0, 50.0, 56.0]
	for lvl in range(1, 6):
		sn.stake_level = lvl
		assert_eq(sn.radius, expected[lvl - 1], "stake %d outer radius" % lvl)
		assert_eq(sn.inner_radius, expected[lvl - 1] - 8.0, "stake %d inner radius" % lvl)


func test_radius_is_derived_not_stored() -> void:
	# The compounding bug in one assertion: the authored knob must never absorb
	# the growth, no matter how many times stake is changed.
	var sn := _make()
	for lvl in [3, 1, 4, 2, 4]:
		sn.stake_level = lvl
	assert_eq(sn.base_radius, 32.0, "base_radius is untouched by stake changes")
	assert_eq(sn.radius, 50.0, "radius reflects only the CURRENT stake level")


func test_stake_set_before_entering_the_tree_still_grows() -> void:
	# Regression: the old capture-on-_ready scheme guarded on is_inside_tree()
	# and silently dropped a pre-tree stake, leaving a stake-4 node rendering
	# and COLLIDING at stake-1 size with no error.
	var sn: SkillNode = SkillNodeScene.instantiate()
	sn.stake_level = 4
	assert_eq(sn.radius, 50.0, "derived radius is correct before the node is in the tree")
	add_child_autofree(sn)
	await get_tree().process_frame
	assert_eq(sn.radius, 50.0, "and stays correct after _ready")
	var shape: CircleShape2D = sn.get_node("CollisionShape2D").shape
	assert_eq(shape.radius, 50.0, "collision follows the derived radius")


func test_authoring_base_radius_rebases_the_growth() -> void:
	var sn := _make()
	sn.stake_level = 3
	sn.base_radius = 48.0
	assert_eq(sn.radius, 60.0, "growth applies on top of the newly authored base")
	sn.stake_level = 1
	assert_eq(sn.radius, 48.0, "and unstaking returns exactly to the authored base")


func test_changing_the_delta_re_derives() -> void:
	var sn := _make()
	sn.stake_level = 5
	sn.stake_radius_delta = 10.0
	assert_eq(sn.radius, 72.0, "base 32 + 4 levels x 10")


func test_radius_change_notifies() -> void:
	var sn := _make()
	watch_signals(sn)
	sn.stake_level = 2
	assert_signal_emitted(sn, "radius_changed", "stake growth notifies listeners")
	sn.base_radius = 40.0
	assert_signal_emit_count(sn, "radius_changed", 2, "so does authoring the base")
