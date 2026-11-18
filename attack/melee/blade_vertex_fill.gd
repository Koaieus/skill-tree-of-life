class_name BladeVertexFill
extends RefCounted
## The one per-vertex fill a blade gets from its source [SkillNode]s: what a
## swing reads per vertex, then the addon dispatch. Both the plan's
## [method MeleeAttackPlan.build_blade_state] and the visual
## [method SkillBlade.build_from_skill_nodes] fill through this, so preview,
## AI scoring and the live swing cannot drift on a vertex's numbers.
##
## Contract: [param nodes] is index-aligned with the [BladeState] particles.
## Stats are read first, addons dispatched after, so an addon's
## [method SkillNodeAddon.apply_to_blade] sees the filled arrays.
## No per-EDGE fill: ADR 0005 — an edge carries no stats.

## The stats a swing reads per vertex, each a localized read (wielder base
## merged with node-local modifiers, e.g. a spike). Index-paired with
## [constant STATE_ARRAYS]; anything that lints "what a vertex reads" reads
## this list.
const VERTEX_STATS: Array[StringName] = [&"blade_damage", &"blunting"]
## The [BladeState] array each of [constant VERTEX_STATS] lands in.
const STATE_ARRAYS: Array[StringName] = [&"vertex_damage", &"vertex_blunting"]


## Optional `(node: SkillNode, stat_id: StringName) -> Array[ModifierBins]`:
## extra bins folded into a vertex's read, after the node's own — a swing's
## temp upgrades ([method MeleeAttackPlan.overlays_for]). Only
## [constant VERTEX_STATS] are ever asked, which is what makes a temp's other
## modifiers inert for the swing. Empty: the plain localized read.
var overlays_for: Callable


func fill(state: BladeState, nodes: Array[SkillNode]) -> void:
	# The copy first: a Frozen copy overlays its vertex's `blade_damage` read.
	_copy_terrain(state, nodes)
	for k in VERTEX_STATS.size():
		# Packed arrays copy on read, so the column is built whole and set.
		var column := PackedFloat32Array()
		column.resize(nodes.size())
		for i in nodes.size():
			column[i] = _read(nodes[i], VERTEX_STATS[k], _frozen_overlay(state, i, nodes[i], VERTEX_STATS[k]))
		state.set(STATE_ARRAYS[k], column)
	state.vertex_node.assign(nodes)
	_flag_frozen(state, nodes.size())
	for i in nodes.size():
		for addon in nodes[i].get_addons():
			addon.apply_to_blade(state, i)


func _read(node: SkillNode, stat_id: StringName, own: Array[ModifierBins] = []) -> float:
	var overlays: Array[ModifierBins] = []
	if overlays_for.is_valid():
		overlays.append_array(overlays_for.call(node, stat_id))
	overlays.append_array(own)
	if not overlays.is_empty():
		var v: Variant = node.get_local_value_with(stat_id, overlays)
		if v != null:
			return float(v)
	return float(node.get_local_value(stat_id))


## Vertex [param i]'s copy as Ice's Frozen answer reads it: the band's
## [FrozenAdmits] and the copy's excess over T, or null when the copy is not
## Frozen (nor Deep freeze).
static func _frozen_copy(state: BladeState, i: int) -> Array:
	var ice := ElementRoster.shared().by_id(&"ice")
	if ice == null or i < 0 or i >= state.vertex_t.size():
		return []
	var read := state.copy_read(i)
	var band := read.band(ice)
	if band == null or not band.admits is FrozenAdmits:
		return []
	return [band.admits, Terrain.excess(read.count(ice), read.threshold)]


## A Frozen vertex's concentrate overlay: one MULTIPLY bin on its
## `blade_damage` read, `1 + vertex_bonus_per_excess × excess` (no base term).
## Every other stat, and a vertex whose copy is not Frozen, gets none.
func _frozen_overlay(state: BladeState, i: int, node: SkillNode, stat_id: StringName) -> Array[ModifierBins]:
	var out: Array[ModifierBins] = []
	if stat_id != &"blade_damage" or node == null:
		return out
	var frozen := _frozen_copy(state, i)
	if frozen.is_empty():
		return out
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = 1.0 + (frozen[0] as FrozenAdmits).vertex_bonus_per_excess * float(frozen[1])
	var bins := ModifierBins.new()
	bins.board = node.node_board
	bins.add(m, node.node_board)
	out.append(bins)
	return out


## A Frozen vertex is one-shot ([member BladeState.vertex_one_shot]): its first
## contact lands, then [BladePopResolver.LiveGate] pops it.
static func _flag_frozen(state: BladeState, n: int) -> void:
	for i in mini(n, state.vertex_one_shot.size()):
		if not _frozen_copy(state, i).is_empty():
			state.vertex_one_shot[i] = 1


## Each source node's terrain onto its vertex's copy, read off the node's live
## slice as its stats are: a read, so the source keeps its stacks.
func _copy_terrain(state: BladeState, nodes: Array[SkillNode]) -> void:
	for i in mini(nodes.size(), state.vertex_t.size()):
		var read := TerrainRead.of(nodes[i].get_combat() if nodes[i] != null else null, nodes[i])
		state.vertex_t[i] = read.t
		state.vertex_charge[i] = read.charge
		state.vertex_threshold[i] = read.threshold
		state.vertex_cap[i] = read.cap
