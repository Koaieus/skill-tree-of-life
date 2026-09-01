class_name CurlCastProbe
extends RefCounted

## The other half of #705: what a [b]real cast[/b] does on a real graph, so the
## linear model in [CurlOperator] can be checked against it instead of trusted.
##
## [CurlOperator] cannot represent [member CycloneStep.closing_gain], the
## momentum merge, or the merge's collapse of N fronts into one — all three need
## the front's history — so the rules the sweep cannot price are priced here, by
## resolving the shipped `cyclone.tres` through [SpellResolver] on a graph built
## from the same sampled terrain the operator measured.
##
## [b]The defender is given enormous HP on purpose.[/b] A cast that kills as it
## goes propagates into fewer nodes on the next wave (#536 — wave N+1's filter
## reads a world in which wave N's kills already happened), which is real
## gameplay and pure noise for a growth measurement: it would confound the
## coefficients' effect with the map's HP roll. What is measured here is the
## walk, not the body count.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _CYCLONE := preload("res://attack/spell/defs/cyclone.tres")

## HP per node, far above anything one cast can chew through.
const _NODE_HEALTH := 1.0e7

var graph: Graph
var attacker: Entity
var defender: Entity


## Builds a live [Graph] from [param terrain] under [param parent], with every
## node but [param caster_index] allocated to a hostile defender.
static func build(terrain: CurlTerrain, caster_index: int, parent: Node) -> CurlCastProbe:
	var probe := CurlCastProbe.new()
	probe.graph = _GRAPH_SCENE.instantiate()
	probe.graph.name = "SpectrumGraph"
	parent.add_child(probe.graph)
	for i in terrain.positions.size():
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = terrain.positions[i]
		probe.graph.skill_nodes_container.add_child(sn)
	var nodes := probe.graph.get_skill_nodes()
	for u in terrain.positions.size():
		for v in terrain.adjacency[u]:
			if v <= u:
				continue
			var e := _EDGE_SCENE.instantiate() as Edge
			e.from = nodes[u]
			e.to = nodes[v]
			probe.graph.edges_container.add_child(e)

	probe.attacker = probe._make_entity("Caster", Color.RED)
	probe.defender = probe._make_entity("Holder", Color.BLUE)
	var alloc := AllocationSystem.new()
	alloc.name = "SpectrumAllocation"
	alloc.graph = probe.graph
	probe.graph.add_child(alloc)
	alloc.force_allocate(probe.attacker, nodes[caster_index])
	probe.attacker.core_location = nodes[caster_index]
	for i in nodes.size():
		if i == caster_index:
			continue
		alloc.force_allocate(probe.defender, nodes[i])
		if probe.defender.core_location == null:
			probe.defender.core_location = nodes[i]
	return probe


## Damage landing per wave for a cast seeded on [param target_index] from the
## caster's own node, normalised to the seed impact: `[1.0, E_1, E_2, …]`.
##
## [param overrides] is applied to a DUPLICATE of the shipped [CycloneStep], so
## a sweep can move `rank_coefficients` / `closing_gain` without editing
## `cyclone.tres` — the same live-tuning door the spell playground uses.
##
## [param include_crits] defaults to FALSE and the shipped [CycleCritCondition]
## is stripped when it is: a crit doubles what a closing hop LANDS without
## changing what it forwards, so leaving it in would add a term the operator
## has no counterpart for on top of the one (`closing_gain`) this probe exists
## to price. Turn it on to read damage a player would actually see.
func wave_damage(
		target_index: int,
		caster_index: int,
		overrides: Dictionary = {},
		include_crits: bool = false) -> PackedFloat64Array:
	var nodes := graph.get_skill_nodes()
	var spell: SpellDef = _CYCLONE.duplicate(true)
	var config: PropagationConfig = spell.propagation
	var step: CycloneStep = config.step.duplicate(true)
	for key in overrides:
		step.set(key, overrides[key])
	config.step = step
	if not include_crits:
		var no_crits: Array[CritCondition] = []
		spell.crit_conditions = no_crits
	var outcome := SpellResolver.resolve(
			spell, nodes[target_index], nodes[caster_index], attacker, graph)
	var per_beat: Dictionary = {}
	for ev in outcome.timeline:
		for hit in ev.hits:
			per_beat[ev.beat] = float(per_beat.get(ev.beat, 0.0)) + hit.amount
	var seed_amount := float(per_beat.get(0, 0.0))
	var out := PackedFloat64Array()
	if seed_amount <= 0.0:
		return out
	# Indexed by beat up to the LAST one that landed, with a beat nothing
	# reached reading 0.0 — never "stop at the first missing key". A wave whose
	# every front was filtered out is a real, informative zero, and truncating
	# there would silently report a short cast as a whole one.
	var last := 0
	for beat in per_beat:
		last = maxi(last, int(beat))
	for beat in last + 1:
		out.append(float(per_beat.get(beat, 0.0)) / seed_amount)
	return out


## A neighbour of [param index] with graph degree at least [param min_degree] —
## a legal Cyclone target adjacent to the caster, which is the seed state the
## operator models (`(caster → target)`). -1 when the caster's node has none.
static func castable_neighbour(terrain: CurlTerrain, index: int, min_degree: int = 4) -> int:
	for nb in terrain.adjacency[index]:
		if terrain.degree(nb) >= min_degree:
			return nb
	return -1


func _make_entity(display_name: String, color: Color) -> Entity:
	var ent := Entity.new()
	ent.display_name = display_name
	ent.color = color
	var camp := Faction.new()
	camp.id = StringName("spectrum_%s" % display_name.to_lower())
	camp.display_name = display_name
	ent.faction = camp
	ent.stat_board = _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	var crit: Stat = ent.stat_board.get_stat(&"crit_chance")
	if crit != null:
		crit.base_value = 0.0
	var health: Stat = ent.stat_board.get_stat(&"node_health")
	if health != null:
		health.base_value = _NODE_HEALTH
	graph.add_child(ent)
	return ent
