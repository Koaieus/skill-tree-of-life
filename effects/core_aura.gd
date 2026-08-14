@abstract
class_name CoreAura
extends Resource

## A [CoreClass] aura emanating from the core's node (D-10). Radiates
## `value_at_hop(h) = base * (1 - h / hop_range)`, clamped at 0, over the entity's
## OWNED subgraph — never the global navigator (see `.claude/rules/graph.md`
## "Reach queries"). Applied at turn start (see `Entity._on_turn_started`),
## once per owned node, outside the D-9 regen gate.
##
## [b]The aura is a channel, not a payload.[/b] This base only answers "how
## much reaches this hop" — what that quantity DOES to a node (heal it, buff
## its armor, ...) is the concrete subclass's job via [method apply]. Do not
## fold "aura == healing" into this base.
##
## Both [member base] and [member hop_range] are authored explicitly, never
## derived from one another: with a fixed per-hop step the range would equal
## the base, so a strong aura would automatically be a wide one and covered
## node count would grow ~quadratically with radius. Bounding coverage is the
## point (see D-10's "sanctuary bubble" note) — two independent knobs let an
## aura get stronger without getting wider.

## Magnitude at the source (hop 0). # TBD (#268) — placeholder pending tuning.
@export var base: float = 0.0
## Hop distance at which the value reaches (and clamps to) 0. Authored
## explicitly — see the class doc above. # TBD (#268) — placeholder pending tuning.
##
## NOT named `range`: a member by that name shadows GDScript's built-in
## `range()` inside this class and every subclass, so `for i in range(n)` there
## becomes a call on a float.
@export var hop_range: float = 0.0


## Linear falloff: base * (1 - h/hop_range), clamped at 0. `hop_range <= 0`
## means no aura at all (avoids a divide-by-zero rather than reading as
## "infinite").
func value_at_hop(h: float) -> float:
	if hop_range <= 0.0:
		return 0.0
	return maxf(base * (1.0 - h / hop_range), 0.0)


## Every node reachable from [param source] within [member hop_range] hops over
## [param mirror] (pass the OWNED subgraph — `entity.navigator` — never the
## global one), mapped to its aura value at that hop. One BFS via
## [method HopRangeFinder.gather], never `in_range` in a loop — see
## `.claude/rules/graph.md` "Reach queries". Zero-value nodes (at or beyond
## range) are omitted.
func values_from(source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var finder := HopRangeFinder.new()
	finder.max_hops = int(ceil(hop_range))
	var hops := finder.gather(source, mirror)
	for node in hops:
		var v := value_at_hop(hops[node])
		if v > 0.0:
			out[node] = v
	return out


## Apply this aura's [param value] (already falloff-scaled for [param node]'s
## hop) to [param node]. Subclasses decide what the channel carries; this
## base makes no assumption.
@abstract func apply(node: SkillNode, value: float) -> void
