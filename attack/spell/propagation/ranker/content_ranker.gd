@tool
class_name ContentRanker
extends NodeRanker

## Scores a node by what it CARRIES: its rolled [member SkillNode.modifiers],
## its [SpellGrant] effects and its attached addons, each by its own weight.
## Defile's stack scale — a blank node scores 0.
##
## An addon counts as a whole: its entity modifiers join
## [member SkillNode.modifiers] on attach ([method SkillNode.add_entity_modifier]),
## so they are excluded by identity here rather than counted twice. Its local
## modifiers live on the separate local ledger and are never read.
##
## Content is topology-static within a cast, so this reads the live node; the
## [param lctx] is unused.

@export var modifier_weight: float = 1.0
@export var grant_weight: float = 2.0
@export var addon_weight: float = 2.0


func score(node: SkillNode, _lctx: LandingContext) -> float:
	if node == null:
		return 0.0
	var addons := node.get_addons()
	var from_addons: Dictionary = {}
	for a in addons:
		for m in a.get_entity_modifiers():
			from_addons[m] = true
	var rolled := 0
	for m in node.modifiers:
		if m != null and not from_addons.has(m):
			rolled += 1
	var grants := 0
	for e in node.effects:
		if e is SpellGrant:
			grants += 1
	return rolled * modifier_weight + grants * grant_weight + addons.size() * addon_weight


func get_description() -> String:
	return "the node's content (modifiers, spell grants, addons)"
