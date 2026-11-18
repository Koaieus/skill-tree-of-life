extends GutTest

## [method HitGather._clone]: a go-off copy or a break's extra landing is a
## fresh landing — it carries none of its source's landing results, the
## recorded pop cue ([member HitInstance.popped_vertex]) included: the pop
## belongs to the one contact that made it.


func test_a_clone_carries_no_pop() -> void:
	var popped: SkillNode = autofree(SkillNode.new())
	var reached: SkillNode = autofree(SkillNode.new())
	var src := DamageInstance.new()
	src.amount = 10.0
	src.popped_vertex = popped
	var a := Arrival.new()
	a.node = reached
	a.head = src
	var c := HitGather._clone(src, a)
	assert_eq(c.target, reached, "the clone lands on the arrival's node")
	assert_null(c.popped_vertex, "the clone carries no pop")
	assert_eq(src.popped_vertex, popped, "the source keeps its pop")
