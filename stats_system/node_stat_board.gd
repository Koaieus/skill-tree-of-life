@tool
class_name NodeStatBoard
extends StatBoard

## The stat board a [SkillNode] carries. Sibling of [EntityStatBoard], NOT a
## subclass of it — a node board is not a specialization of an entity board;
## the two overlap on ids, not on shape. Both inherit their whole mechanism
## (lookup, modifier routing, binding, cycle detection) from [StatBoard], which
## holds no stat fields of its own.
##
## [b]Bake what the node owns; stay sparse for what it borrows.[/b] The split
## is not a memory compromise — it falls out of how a combined read works.
## [method SkillNode.get_local_value] merges an owned node's value as
## [code]ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])[/code],
## so for any id the entity ALSO carries, a node-board stat's own `base_value`
## is silently discarded and only its bins count. Authoring `armor = 5` here
## would do nothing, with no error. Therefore:
##
## - [b]Node-only stats[/b] (nothing on the entity board shadows them) get real
##   typed fields with meaningful authored defaults, baked into
##   `skill_node/default_node_board.tres` the way `default_entity_board.tres`
##   works. Their `base_value` is live, and nothing has to mint them in code.
## - [b]Borrowed stats[/b] (`armor`, `node_healing`, `blade_damage`, …) stay
##   dynamic in [member StatBoard._extra_stats], created only when a node-local
##   modifier actually targets them. There is nothing to author, so a field
##   would buy nothing and cost one Stat per node across a 500–2500-node level
##   (see .claude/rules/skill-node-scale.md).
