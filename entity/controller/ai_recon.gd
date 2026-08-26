class_name AiRecon
extends RefCounted

## Fog-aware enemy recon for AI v1 (#378). Per-entity vision, not the shared
## player-only [VisionSystem] instance (game_root's `%VisionSystem`, whose
## `viewers` is `[player]` and drives the player's fog rendering only) —
## settled 2026-08-07: "each enemy acts only on what it personally sees", no
## faction-shared reveal in v1.
##
## The vision RULE stays single-sourced in [VisionCircles] (shared with
## [VisionSystem], which builds one of the same sets per recompute) —
## this module only supplies the WHO (this entity's owned nodes, off
## [member Entity.navigator], the per-entity subgraph mirror) and evaluates
## fresh per AI turn instead of touching the shared singleton's cached
## viewer-scoped state. Two call sites, one geometry, never two
## implementations of "is X visible".
##
## Recon depth for the cut-vertex/island walk is bounded separately from
## vision range: `recon_bound()` is attack reach + 1 allocation, deliberately
## decoupled from SP bank size so a large-SP entity doesn't scan the whole
## board (tier-2 knob: full SP+DP reach, not v1).


## True if [param entity] currently sees at least one hostile-owned node.
static func has_visible_hostile(entity: Entity) -> bool:
	return not visible_enemy_nodes(entity).is_empty()


## Every enemy-owned [SkillNode] within vision range of any of [param entity]'s
## owned nodes, minus the camps that don't draw AI attention
## ([member Faction.targeted_by_ai] — dormant-core blockers, unless this
## entity is boxed in; see [method is_ai_target]). This is the one
## chokepoint every NPC target list flows through: growth's directional bias,
## the `saw_hostile` short-circuit, and the ranged/magic/melee candidate
## enumerations all consume what this returns, so the filter belongs here and
## not in [method Entity.attitude_to] (which must keep reading HOSTILE so the
## *player* can still clear a blocker).
static func visible_enemy_nodes(entity: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if entity == null or entity.navigator == null or entity.navigator.graph == null:
		return out
	var graph := entity.navigator.graph
	var owned := entity.navigator.get_mirrored_nodes()
	if owned.is_empty():
		return out
	var circles := VisionCircles.new()
	for src in owned:
		circles.add(src.global_position, float(src.get_local_value(&"vision_range")))
	for node in graph.get_skill_nodes():
		if node == null or node.owned_by == null:
			continue
		if not is_ai_target(entity, node):
			continue
		if circles.has_point(node.global_position):
			out.append(node)
	return out


## Is [param node] something [param attacker]'s brain should want to hurt?
## HOSTILE (the relation, [method Entity.attitude_to]) AND owned by a camp
## whose [member Faction.targeted_by_ai] is true — dormant-core blockers fail
## the second half while staying hostile to everyone else, including the
## player.
##
## [b]Unless the attacker is boxed in AND this is the wall[/b] —
## [member Entity.ai_growth_capped], set per turn from [method is_growth_capped],
## flips the second half back on for cores that [method borders_territory].
## An NPC with nowhere left to allocate is not being patient by ignoring the
## scenery that walls it in, it is stuck; a Dormant Core is then the cheapest
## door out (and pays a relic for opening it). Indifference is the default
## stance, not a rule.
##
## The bordering half is not decoration: an entity capped by its own ALLIES has
## no door at all, and without it that entity would unlock — and spend its AP
## on — some unreachable core across the map that opens nothing. A core you
## cannot allocate around is not what is capping you; the wall is adjacent by
## definition, and a core further out only becomes reachable after a node next
## to it is allocated, which a capped entity cannot do anyway.
##
## THE one definition, used both to build target lists ([method
## visible_enemy_nodes]) and to value a resolved swing ([method
## AiCombatScorer.expected_damage]) — an AoE/blade that merely clips a blocker
## must not score for it either, or the filter is cosmetic and the AI still
## steers into scenery. Both consumers already pass the attacker, which is why
## the stance rides on [Entity] rather than being threaded through as a param.
static func is_ai_target(attacker: Entity, node: SkillNode) -> bool:
	if attacker == null or node == null or node.owned_by == null:
		return false
	if attacker.attitude_to(node.owned_by) != Entity.Attitude.HOSTILE:
		return false
	var owner_faction: Faction = node.owned_by.faction
	if owner_faction == null or owner_faction.targeted_by_ai:
		return true
	return attacker.ai_growth_capped and borders_territory(node, attacker)


## Every unowned node adjacent to one [param entity] already owns — its growth
## frontier, and THE definition of one (the AI's allocation step and the
## capped test below both read it, never a second walk).
##
## A node held by a Dormant Core is owned, so it is never frontier: killing the
## core is what turns it into one.
static func frontier_nodes(entity: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var graph: Graph = entity.navigator.graph \
			if entity != null and entity.navigator != null else null
	if graph == null:
		return out
	var seen: Dictionary[SkillNode, bool] = {}
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var a := edge.from
		var b := edge.to
		if a.owned_by == entity and b.owned_by == null and not seen.has(b):
			seen[b] = true
			out.append(b)
		if b.owned_by == entity and a.owned_by == null and not seen.has(a):
			seen[a] = true
			out.append(a)
	return out


## Does [param node] touch [param entity]'s own territory? THE definition of a
## "door" for a capped entity: depleting a node force-deallocates it, so a
## bordering node lands in [method frontier_nodes] the very next pass.
##
## Two readers, one rule — the blocker unlock in [method is_ai_target] and the
## breakout bonus in [method AiCombatScorer.score].
##
## Adjacency, not degree: the question is membership in the neighbour set, so
## [method Graph.get_neighbours] is the right call and the degree rule does not
## apply.
static func borders_territory(node: SkillNode, entity: Entity) -> bool:
	if node == null or entity == null or entity.navigator == null:
		return false
	var graph: Graph = entity.navigator.graph
	if graph == null:
		return false
	for neighbour in graph.get_neighbours(node):
		if neighbour != null and neighbour.owned_by == entity:
			return true
	return false


## Has [param entity] run out of room to grow? Purely topological — it asks
## whether ANY node is allocatable at all, never whether the entity can afford
## one right now (SP is a budget, not a wall, and an entity that banks SP with
## nowhere to spend it is exactly the case this answers "yes" for).
##
## Drives [member Entity.ai_growth_capped]: capped is the one state in
## which an NPC stops treating a Dormant Core as scenery.
static func is_growth_capped(entity: Entity) -> bool:
	return frontier_nodes(entity).is_empty()


## Attack-reach + 1-allocation bound. [param max_reach] is the largest
## per-mode attack reach available to [param entity] this turn — callers
## supply it since mode reach math (ranged/magic/melee) lives outside this
## module.
static func recon_bound(max_reach: float, allocation_cost: float = 1.0) -> float:
	return max_reach + allocation_cost


## Cut vertices in [param entity]'s own territory within [param bound] scene-
## pixels of its core — nodes that would island other owned nodes if
## depleted. Used both defensively (own weak points) and offensively (a
## hostile entity's cut vertices are high-value strike targets).
static func cut_vertices_within(entity: Entity, bound: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if entity == null or entity.navigator == null or entity.core_location == null:
		return out
	var core: SkillNode = entity.core_location
	for n in entity.navigator.get_mirrored_nodes():
		if n == core:
			continue
		if core.global_position.distance_to(n.global_position) > bound:
			continue
		if entity.navigator.would_disconnect_from(n, core):
			out.append(n)
	return out
