@tool
class_name GraphProcgenTopology
extends Resource

## Topology module (#349). Node count, spacing and connectivity — the knobs a
## lobby's Map size XS..XXL control turns. Save as its own top-level `.tres`
## under `procgen/modules/<preset>/` and reference it by path from a
## [GraphProcgenConfig.topology] — never embed it as a SubResource, or a
## lobby has nothing to point at when swapping map size (#349 D3).

## Target node count. Poisson sampling stops when the active list empties,
## so the actual count is bounded by what the shape + spacing allow.
@export_range(50, 3000, 10) var node_count: int = 300
## Visual + collision radius pushed onto every generated SkillNode.
@export_range(1., 64., 1.) var node_radius: float = 32.0
## Extra clearance between nodes beyond `2 × node_radius`. Higher = airier.
@export_range(1., 128., 1.,) var node_padding: float = 14.0
## Fraction of Delaunay edges to keep beyond the minimum spanning tree.
## 0 = MST only (every node connected, sparsest planar). 1 = full Delaunay
## (densest planar). Spans shortest-edges-first so the result stays organic.
@export_range(0.0, 1.0) var connectivity: float = 0.55

@export_subgroup("Self-loops")
## 4-tier floor-guaranteed staged self-loop draw (#42). Tier 1 draws
## `floor(N × p1)` nodes uniformly from all generated nodes (without
## replacement); tier k draws `floor(K_{k-1} × p_k)` from the previous tier's
## set. Each tier then does ONE Bernoulli on the fractional remainder to add
## +1 (floor + 0-or-1), and a node that hits tier k gets exactly k self-loops.
## Cores are NOT excluded from the tier-1 pool. The number of tier knobs IS
## the cap (4) — raising it later means adding a tier-5 knob.
@export_range(0.0, 1.0) var self_loop_tier1_rate: float = 0.10
## Fraction of the tier-1 set upgraded to exactly 2 self-loops.
@export_range(0.0, 1.0) var self_loop_tier2_rate: float = 0.17
## Fraction of the tier-2 set upgraded to exactly 3 self-loops.
@export_range(0.0, 1.0) var self_loop_tier3_rate: float = 0.30
## Fraction of the tier-3 set upgraded to exactly 4 self-loops (the cap).
@export_range(0.0, 1.0) var self_loop_tier4_rate: float = 0.30
