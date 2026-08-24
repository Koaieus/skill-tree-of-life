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
##
## Note `node_health` stays on the borrowed side despite being the node's own
## combat pool: the entity board carries that id too (as the ScalarStat
## baseline the pool re-syncs from), so it is shadowed by the rule above. What
## it needs is a different Stat CLASS per board, and that is what
## [method _mint_stat] handles.

## Per-node allocation cap and fill in one pool: `.value` (cap) is the stake
## level — the N in the M/N dial — and `.current` is the allocation level, the
## M. 0 = unowned, 1 = baseline, 2+ = staked (#374). The pool's own clamp is
## the single guard keeping fill ≤ cap.
##
## [member SkillNode.stake_level] / [member SkillNode.allocation_level] are
## proxy properties over this, so authors stay at SkillNode scope and never
## open the board.
@export var stake_level: PoolStat

## How many addons this node may carry (#375). `base(0) + allocation_level`,
## via an ADD_BASE modifier whose formula reads the `stake_level__current`
## accessor — authored in `intrinsic_modifiers` on
## `skill_node/default_node_board.tres`, not built in code, so the curve is a
## one-file edit and the reactive rebind is the ordinary one.
##
## Advisory, not enforced: nothing caps attachment yet, and procgen mints
## addons while nodes are unowned (`allocation_level == 0`). See #348.
@export var addon_slots: ScalarStat


## Node boards are the sparse side — they legitimately mint the stats they
## borrow from their owner (`armor`, `node_healing`, `blade_damage`, …), so the
## registry default applies. The one exception is `node_health`: the entity
## board's `node_health` is the ScalarStat BASELINE, while the node needs a
## combat POOL (max + current) built from the `node_combat_health` def. Same id,
## different Stat class per board — which is precisely a fact about this board
## class, so it lives here instead of as a hardcoded branch in
## [method SkillNode._ensure_local_stat] reaching into `_extra_stats` directly.
func _mint_stat(stat_id: StringName) -> Stat:
	if stat_id != &"node_health":
		return super(stat_id)
	var def: StatDef = StatRegistry.get_def(&"node_combat_health")
	if def == null:
		push_warning("NodeStatBoard._mint_stat: node_combat_health def missing")
		return null
	var hp := PoolStat.new()
	hp.definition = def
	hp._set_base_minted(def.default_value)  # seed, not a cap change (#555)
	_extra_stats[stat_id] = hp
	return hp
