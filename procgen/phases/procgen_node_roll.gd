@tool
class_name ProcgenNodeRoll
extends RefCounted

## The per-node roll of [method GraphProcgen.generate] (hub #422, child 5),
## extracted from `graph_procgen.gd` with its body unchanged: authored-scene
## instantiation, the blocker/skill scene pick, archetype stamping, the budget
## and subtype rolls, the modifier draw, and the spell-grant / addon pool
## bookkeeping. Static and stateless — [GraphProcgen] derives the subtype
## stream from its own salt and hands it in, owns the loop and every progress
## emit, and this phase never touches the callback. One call rolls one node
## (rather than the whole loop) precisely so `generate` keeps its mid-loop
## progress emits. Same seed → byte-identical graph is guarded by
## `test/integration/procgen/test_procgen_golden.gd`.
## See docs/domain/procgen.md and docs/domain/procgen-v4.md.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BLOCKER_NODE_SCENE := preload("res://skill_node/blocker_node.tscn")


## Rolls and instantiates node `i`, appending it to `nodes` and, where the
## post-loop passes expect it, to `addon_eligible` / `int_nodes`. The draw
## order is exactly the old loop body's. Returns false for an authored-scene
## node (the old loop's `continue`): the caller skips its progress tail for it,
## as the loop always did.
static func run(
		i: int,
		positions: Array[Vector2],
		graph: Graph,
		placement_ctx: PlacementContext,
		type_assignments: PackedInt32Array,
		blocker_sizes: Dictionary,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
		subtype_rng: RandomNumberGenerator,
		default_subtype: NodeSubtype,
		subtype_drawable: Dictionary,
		nodes: Array[SkillNode],
		int_nodes: Array[SkillNode],
		addon_eligible: Array[SkillNode],
) -> bool:
	var sn: SkillNode
	var authored_scene: PackedScene = placement_ctx.scenes[i]
	if authored_scene != null:
		# An authored-scene node is PURE: the scene IS the content.
		# Procgen sets its position and nothing else — no archetype, no
		# budget, no modifier roll, no rolled addons, no radius stamp (the
		# scene's authored radius stands), never a blocker (eligibility
		# excluded it), never in the spell-grant pool.
		sn = authored_scene.instantiate()
		sn.position = positions[i]
		if not placement_ctx.role_tags[i].is_empty():
			sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
		graph.add_skill_node(sn)
		nodes.append(sn)
		return false
	if blocker_sizes.has(i):
		sn = _BLOCKER_NODE_SCENE.instantiate()
	else:
		sn = _SKILL_NODE_SCENE.instantiate()
	sn.position = positions[i]
	var archetype_id: StringName = &""
	var archetype_color: Color = Color.WHITE
	var archetype_forbid: Array[StringName] = []
	var archetype_primary_stat: StringName = &""
	var archetype_resource: Archetype = null
	if type_assignments[i] >= 0:
		var policy: ArchetypePolicy = config.content.archetypes[type_assignments[i]]
		if policy != null and policy.archetype != null:
			archetype_id = policy.id
			archetype_color = policy.archetype.color
			archetype_forbid = policy.forbid_tags
			archetype_primary_stat = policy.archetype.primary_stat
			archetype_resource = policy.archetype
	if archetype_id != &"":
		var fp := {"archetype": archetype_id, "primary_stat": archetype_primary_stat}
		if not placement_ctx.role_tags[i].is_empty():
			fp["role_tags"] = placement_ctx.role_tags[i].duplicate()
		var role_tags: Array = placement_ctx.role_tags[i]
		var budget := 0
		if config.content.budget_policy != null:
			budget = config.content.budget_policy.compute_budget(
					archetype_id, positions[i], role_tags, rng)
		fp["budget"] = budget
		# One draw per archetype-bearing node whenever any subtype is
		# authored — a constant draw count keeps a `base_chance` retune
		# from shifting another node's roll. The budget-0 else branch gets
		# no subtype (nor any content).
		var node_subtype := ProcgenSubtypeRoll.run(
				config.content.subtypes, archetype_primary_stat,
				subtype_drawable, default_subtype, subtype_rng)
		# Radius follows the rolled budget; an authored scene never
		# reaches this branch, so its own radius stands.
		ProcgenPlacement._stamp_radius(sn, config.topology.radius_for_budget(budget))
		if config.content.modifier_pool_set != null:
			sn.authored_modifiers = ProcgenModifierRoller.run(
					config.content.modifier_pool_set, config.content.weight_profiles,
					archetype_id, archetype_primary_stat, archetype_forbid,
					positions[i], i, budget, rng, fp, node_subtype,
					config.content.universal_share,
					config.content.multiply_fuse_floor)
		sn.set_meta("procgen_footprint", fp)
		# Stamps NodeVisualsComposite's archetype_tint (persistent type
		# identity, rim/sensed-outline colour). Owner colour stays free to
		# drive the entity_tint channel via SkillNode.
		sn.base_type_color = archetype_color
		# The archetype's own emblem shape (docs/domain/skillnode-emblem.md) —
		# every archetype carries one now, so this always stamps.
		sn.archetype = archetype_resource
		# The node's second identity — the visuals child reads its tint and
		# emissive tier. Always the resolved value, never null.
		sn.subtype = node_subtype
		sn.set_meta("archetype", archetype_id)
		if archetype_primary_stat != &"":
			sn.set_meta("primary_stat", archetype_primary_stat)
		# Persist role tags for downstream inspection / debug overlays.
		if not placement_ctx.role_tags[i].is_empty():
			sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
	else:
		# No archetype → no budget → the uniform default (budget 0 path).
		ProcgenPlacement._stamp_radius(sn, config.topology.radius_for_budget(0))
	graph.add_skill_node(sn)
	addon_eligible.append(sn)
	if GraphProcgenSpellGrants.is_eligible_node(archetype_primary_stat):
		int_nodes.append(sn)
	nodes.append(sn)
	return true
