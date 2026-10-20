extends GutTest

## [method StatusInstance.stamp_landing]: copies exactly the landing's shared
## facts onto a status hit, and leaves the caller-owned fields alone.


func test_copies_every_shared_fact() -> void:
	var landing := HitLanding.new()
	var origin := SkillNode.new()
	var target := SkillNode.new()
	var read := SkillNode.new()
	var paired := HitInstance.new()
	landing.attacker = Entity.new()
	landing.source = &"src"
	landing.origin = origin
	landing.target = target
	landing.read_node = read
	landing.structural_key = 3.5
	landing.paired = paired
	landing.hit_key = 7
	var def := StatusDef.new()
	var status := StatusInstance.new()
	StatusInstance.stamp_landing(status, def, landing)
	assert_eq(status.def, def)
	assert_eq(status.attacker, landing.attacker)
	assert_eq(status.source, &"src")
	assert_eq(status.origin, origin)
	assert_eq(status.target, target)
	assert_eq(status.read_node, read)
	assert_eq(status.structural_key, 3.5)
	assert_eq(status.paired, paired)
	assert_eq(status.hit_key, 7)
	for n in [landing.attacker, origin, target, read]:
		n.free()


func test_leaves_caller_owned_fields() -> void:
	var landing := HitLanding.new()
	landing.stack_scale = 4.0
	var status := StatusInstance.new()
	status.power = 9.0
	status.raw = true
	StatusInstance.stamp_landing(status, StatusDef.new(), landing)
	assert_eq(status.power, 9.0)
	assert_true(status.raw)
	assert_eq(status.stack_scale, 1.0)
