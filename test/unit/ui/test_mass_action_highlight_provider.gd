extends GutTest

## MassActionHighlightProvider — DEALLOCATE paints every cascade node FORFEIT
## ("this goes away"); anything outside the cascade reads NONE. See #1285.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _a: SkillNode
var _b: SkillNode
var _c: SkillNode


func before_each() -> void:
	_a = add_child_autofree(_SKILL_NODE_SCENE.instantiate())
	_b = add_child_autofree(_SKILL_NODE_SCENE.instantiate())
	_c = add_child_autofree(_SKILL_NODE_SCENE.instantiate())


func test_deallocate_cascade_reads_forfeit() -> void:
	var request := MassActionRequest.new(null, MassActionRequest.Verb.DEALLOCATE, [_a, _b])
	var provider := MassActionHighlightProvider.new()
	provider.configure(request, null)
	assert_eq(provider.get_node_role(_a), HighlightProvider.HighlightRole.FORFEIT)
	assert_eq(provider.get_node_role(_b), HighlightProvider.HighlightRole.FORFEIT)
	assert_eq(provider.get_node_role(_c), HighlightProvider.HighlightRole.NONE)
