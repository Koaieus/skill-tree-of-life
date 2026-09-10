@tool
class_name StatRanker
extends NodeRanker

## Reads a stat value off the candidate via [method SkillNode.get_local_value].
## Use cases: rank by remaining node health (Bruiser homes to the most wounded
## target), by armor (Heavy Bolt), by any future board-stat ranking.
##
## [param stat_id] accepts #333's accessor tokens — `<stat_id>__<accessor>` —
## because [method NodeCombat.get_local_value] understands them (#702). This
## matters for pools: a bare `node_health` reads the pool's CAP, and since #660
## that cap is a live provider off the owner's baseline, so it is very nearly
## the same number on every node one entity owns — ranking by it is mostly
## ties. `node_health__current` is the per-node-varying signal, and is the
## default for that reason.
@export var stat_id: StringName = &"node_health__current"


## Reads through [method PropagationContext.local_value_of], never off the node
## directly: on a shadow world that is how the ranker sees damage this very cast
## dealt on an earlier wave. Ranking by a pool CAP hid the distinction — a cap
## does not move mid-cast — so `node_health__current` is what makes it matter.
## A null [param ctx] (unit tests, hand-built configs) reads the live node,
## which is the same answer [CombatWorld.live] would have given.
func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if node == null:
		return 0.0
	# A node with no such stat answers null, and `float(null)` is an error rather
	# than a 0 — so this guard is load-bearing, not defensive padding.
	var v: Variant = ctx.local_value_of(node, stat_id) if ctx != null \
		else node.get_local_value(stat_id)
	if v == null:
		return 0.0
	return float(v)


## Player-facing, via [method TakeTopNSpread.get_description],
## [method TopTiesFilter.get_description] and [method RankThresholdFilter.get_description]
## into the spell tooltip (#764) — the human [member StatDef.display_name],
## never the raw snake_case id: `node_health__current` reads "remaining node
## health", not "current node_health" (still a leaked identifier) and
## certainly not the bare `__` join.
func get_description() -> String:
	var base_id := StatFormula.base_of(stat_id)
	var def: StatDef = StatRegistry.get_def(base_id)
	var name := def.display_name.to_lower() if def != null else String(base_id).replace("_", " ")
	var accessor := StatFormula.accessor_of(stat_id)
	if accessor == &"current":
		return "remaining %s" % name
	if accessor != &"":
		return "%s %s" % [String(accessor), name]
	return name
