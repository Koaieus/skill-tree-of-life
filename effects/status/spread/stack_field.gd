class_name StackField
extends RefCounted

## A read-only view of ONE [StatusDef]'s raw stacks over a set of
## [NodeCombat]s and their adjacency — what a [StatusSpread] rule reads.
## Built over a [CombatWorld] ([method over_world], live or shadow alike, since
## every read goes through the slices) or straight from a dictionary graph
## (`{NodeCombat: Array[NodeCombat]}`), so every rule is unit-tier.
## Never writes: [SpreadApplier] lands what a rule returns.

var def: StatusDef
## [member StatusSpread.ownership_mask] — [enum SkillNode.Ownership] bits.
var mask: int = SkillNode.Ownership.MINE
var _adjacency: Dictionary = {}
## Which row of [member def] the field reads — `(def.id, key)` (#1343);
## `true` for a shared def. A rule stamps it on every transfer it emits.
var key: Variant = true


func _init(p_def: StatusDef = null, p_mask: int = SkillNode.Ownership.MINE,
		p_adjacency: Dictionary = {}, p_key: Variant = true) -> void:
	def = p_def
	mask = p_mask
	_adjacency = p_adjacency
	key = p_key


## The field over [param nodes] in [param world]: each node's slice, adjacent
## to the slices of its [method Graph.get_neighbours] (all of them — the mask
## filters at read time, so a neighbour outside [param nodes] still counts).
static func over_world(p_def: StatusDef, p_mask: int, world: CombatWorld,
		nodes: Array[SkillNode], graph: Graph, p_key: Variant = true) -> StackField:
	var adjacency := {}
	for node in nodes:
		var around: Array[NodeCombat] = []
		for m in graph.get_neighbours(node):
			around.append(world.combat_for(m))
		adjacency[world.combat_for(node)] = around
	return StackField.new(p_def, p_mask, adjacency, p_key)


## Every host in the field, in insertion order.
func nodes() -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	out.assign(_adjacency.keys())
	return out


## [param n]'s RAW row `(def.id, key)` (ADR 0032: spread moves the raw
## integer row; resistance stays the live filter). `0` when absent.
func stacks(n: NodeCombat) -> float:
	return n.get_status_power(def.id, key) if n != null and def != null else 0.0


## [param n]'s neighbours in [member mask] — [method neighbours_in] with the field's own mask.
func masked_neighbours(n: NodeCombat) -> Array[NodeCombat]:
	return neighbours_in(n, mask)


## [param n]'s neighbours whose [method NodeCombat.ownership_bit] — seen by
## [param n]'s OWNER — is in [param p_mask]. An unowned host has no one to be
## Mine or Ally to: a neutral neighbour reads Neutral, an owned one Hostile.
func neighbours_in(n: NodeCombat, p_mask: int) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	var owner_slice := n.owner() if n != null else null
	var viewer: Entity = owner_slice.real_entity() if owner_slice != null else null
	for m: NodeCombat in _adjacency.get(n, []):
		if m.ownership_bit(viewer) & p_mask != 0:
			out.append(m)
	return out


## How many of [param n]'s neighbours are in [member mask] — the one owner of
## "degree inside a mask" (see docs/domain/degree.md).
func masked_degree(n: NodeCombat) -> int:
	return masked_neighbours(n).size()
