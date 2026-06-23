@tool
@abstract
class_name SpellPropagation
extends Resource

## How a spell walks the graph after seeding. Subclasses answer the recursive
## question — "given the in-flight state at this node, where does the spell
## go next and in what mutated form?" — and the driver ([SpellResolver])
## walks a queue using those answers.
##
## Per-hop damage transform lives here too, not in a separate falloff slot:
## the walk shape and the damage curve are conceptually one thing (Lightning's
## ×0.5 only makes sense in the context of an all-neighbour BFS). Spells
## with no propagation use [NoPropagation] and apply damage formulas via
## [DamageEffect]'s expression hook instead.


## Per-step damage multiplier applied when the spell moves to a neighbour.
## 0.5 = falloff (Lightning), 2.0 = rampup (Crunch), 1.0 = flat (Heavy / Flood).
@export var damage_multiplier_per_hop: float = 1.0

## One-time multiplier baked into the SEED hit's damage — applied once at
## resolve time, not on every hop. 0.25 = Crunch's "1/4 to initial then ramp";
## 1.0 = the seed hit takes full base damage (the common case).
@export var seed_damage_fraction: float = 1.0

## Max recursion depth from the seed. 0 = seed only, no propagation. The
## resolver stops descending when [member CastSpell.hops_remaining] hits 0.
@export var max_hops: int = 0

## If true, the walk may re-enter a previously-hit node. Default false avoids
## A→B→A→B oscillation in dense graphs and lets BFS terminate on hops alone.
@export var revisit_visited: bool = false


## Given the in-flight spell, return the set of states to propagate to next.
## Empty array terminates this branch. Implementations should not mutate
## [param state] — produce fresh [CastSpell] instances via [method _propagate_to].
@abstract func next_hops(state: CastSpell) -> Array[CastSpell]


## One-line human-readable description of this propagation shape, surfaced in
## tooltips / spell cards. Subclasses override; the base returns "" so any
## propagation lacking an override simply renders no description line.
func get_description() -> String:
	return ""


## Helper for subclasses — mints a propagated state with the seed/caster/source
## copied through, hop counters advanced, and the per-hop damage multiplier
## applied. Subclasses call this once per neighbour they're propagating into.
func _propagate_to(neighbour: SkillNode, state: CastSpell) -> CastSpell:
	var next := CastSpell.new()
	next.seed_node = state.seed_node
	next.current_node = neighbour
	next.predecessor = state.current_node
	next.source = state.source
	next.damage = state.damage * damage_multiplier_per_hop
	next.hops_remaining = state.hops_remaining - 1
	next.hop_index = state.hop_index + 1
	next.visited = state.visited.duplicate()
	next.visited.append(neighbour)
	next.caster = state.caster
	next.graph = state.graph
	return next
