@tool
class_name GraphProcgenContent
extends Resource

## Content module (#349). Archetypes + modifier pools + everything that
## decides what a node's content looks like — the knobs a lobby's budget
## min/max ("go HAM", #597 D8) control turns. Save as its own top-level
## `.tres` under `procgen/modules/<preset>/` and reference it by path from
## [GraphProcgenConfig.content] — never embed it as a SubResource (#349 D3).

## Phased-draw modifier content. The per-node v4 draw spends the rolled
## budget until broke across pools whose `archetype_stat` matches the node's
## primary_stat (or is universal `&""`), then aggregates per (stat, op).
## Unset = nodes roll no modifiers. See docs/domain/procgen-v4.md.
@export var modifier_pool_set: ModifierPoolSet
## Typed as Array[Resource] because Godot's TypedArray check rejects
## subclasses of an abstract base — concrete profiles (Archetype/Collision/Radial)
## couldn't coexist in `Array[WeightProfile]`. Runtime dispatches via
## [method WeightProfile.multiplier_for] duck-typing.
@export var weight_profiles: Array[Resource] = []

## Per-node budget knobs — the base range plus archetype / role / positional
## multipliers that decide each node's modifier budget. Unset = budget 0
## (nodes roll no modifiers). See [BudgetPolicy].
@export var budget_policy: BudgetPolicy

## Archetype policies. When non-empty, the cluster pass runs cluster-planned
## BFS-grow using these per-archetype target ratios + size distributions;
## empty leaves every node archetype-less (and content-less).
@export var archetypes: Array[ArchetypePolicy] = []

@export_subgroup("Addons & spell grants")
## Second-pass addon roll. Unset = no addons attached by procgen.
@export var addon_policy: AddonPolicy

## Third-pass spell-grant distribution (#206). Unset (or [member spell_grant_ratio]
## 0) = no grants attached by procgen. Gated to INT-archetype nodes only —
## see [GraphProcgenSpellGrants]. `ratio` is the level's grant budget as a
## fraction of the INT-node count (1.0 = one grant per INT node on average),
## split across the pool's entries by weight and Poisson-rolled per entry —
## every entry in the pool is guaranteed at least one copy on the level.
@export var spell_grant_pool: SpellGrantPool
@export_range(0.0, 1.0) var spell_grant_ratio: float = 0.0

@export_subgroup("Placement & balancing")
## Pre-roll constraints. Each runs against a [PlacementContext] and may stamp
## role tags (consumed by [BudgetPolicy.role_bonus]) or reserve nodes for
## special content. See docs/domain/procgen-v2.md "GuaranteedPlacement".
## Typed Array[Resource] for the same reason weight_profiles is — concrete
## placement subclasses can't coexist in a typed abstract-base array.
@export var guaranteed_placements: Array[Resource] = []

## Optional running-count rebalance for jitter rerolls + fallback assignment.
## See [ArchetypeBalancer]. Off by default; set + flip `enabled` to dampen RNG
## streaks against the target ratios.
@export var archetype_balancer: ArchetypeBalancer

## Post-clustering territory stamps. After BFS-grow archetype assignment
## ([member archetypes]), each stamp overrides the archetype of nodes inside
## its region — a euclidean disc or a topological BFS flood. Stamps run
## before the content-roll loop, so overridden nodes get the new archetype's
## colour, primary-stat bias, and budget multipliers. See [ArchetypeStamp].
@export var archetype_stamps: Array[ArchetypeStamp] = []
