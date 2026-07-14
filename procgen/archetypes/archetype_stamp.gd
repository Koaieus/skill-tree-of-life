@tool
class_name ArchetypeStamp
extends Resource

## Paints an archetype onto a region of nodes — either a euclidean disc or a
## topological BFS flood from a seed. Runs as a post-clustering pass in
## [GraphProcgen] after [method GraphProcgen._assign_archetypes] and before the
## content-roll loop, overriding [code]type_assignments[i][/code] for every node
## inside the region.
##
## EUCLIDEAN stamps find nodes by world-space distance from [member position].
## TOPOLOGICAL stamps BFS-flood up to [member max_hops] from [member seed_node_index]
## along the pruned edge set — respects graph connectivity, so gaps between
## connected components aren't crossed.
##
## Both modes are exposed in the [GraphProcgenConfig] inspector and simulated in
## the procgen playground (#166), so a designer can paint a territory, see which
## nodes it catches, and tune the radius/hops before committing a preset.

enum RegionMode { EUCLIDEAN, TOPOLOGICAL }

@export var mode: RegionMode = RegionMode.EUCLIDEAN

## World-space center of the euclidean disc (EUCLIDEAN mode only).
@export var position: Vector2 = Vector2.ZERO

## Radius of the disc in world units (EUCLIDEAN mode only).
@export var radius: float = 0.0

## Index of the seed node into the position list (TOPOLOGICAL mode only).
## The seed itself is always included in the stamped set.
@export var seed_node_index: int = -1

## Max number of BFS hops outward from [member seed_node_index] (TOPOLOGICAL only).
## 0 = seed only; 1 = seed + direct neighbours; etc.
@export var max_hops: int = 2

## Index into [member GraphProcgenConfig.archetypes] — the archetype identity
## assigned to every node caught by this stamp.
@export var archetype_idx: int = 0
