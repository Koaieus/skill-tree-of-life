@tool
class_name GraphProcgenContent
extends Resource

## Content module (#349). Archetypes + modifier pools + everything that
## decides what a node's content looks like — the knobs a lobby's budget
## min/max ("go HAM", #597 D8) control turns. Save as its own top-level
## `.tres` under `procgen/modules/<preset>/` and reference it by path from
## [GraphProcgenConfig.content] — never embed it as a SubResource (#349 D3).

## Phased-draw modifier content. The per-node v4 draw spends the rolled
## budget until broke across packs whose `archetype_stat` matches the node's
## primary_stat (or is universal `&""`), then aggregates per (stat, op).
## Unset = nodes roll no modifiers. See docs/domain/procgen-v4.md.
@export var modifier_pool_set: ModifierPoolSet
## Typed as Array[Resource] because Godot's TypedArray check rejects
## subclasses of an abstract base — concrete profiles (Archetype/Collision/Radial)
## couldn't coexist in `Array[WeightProfile]`. Runtime dispatches via
## [method WeightProfile.multiplier_for] duck-typing.
@export var weight_profiles: Array[Resource] = []

const DEFAULT_UNIVERSAL_SHARE := 0.2
## Share of every modifier pick that goes to universal (`archetype_stat ==
## &""`) content, whatever the node's archetype — a share of picks, not of
## budget points. Renormalized over what is drawable at each pick: when one
## side has nothing drawable, the other takes the whole pick. See
## [method GraphProcgen._v4_pick_distribution] and docs/domain/procgen-v4.md.
@export_range(0.0, 1.0) var universal_share: float = DEFAULT_UNIVERSAL_SHARE

## Per-node budget knobs — the base range plus archetype / role / positional
## multipliers that decide each node's modifier budget. Unset = budget 0
## (nodes roll no modifiers). See [BudgetPolicy].
@export var budget_policy: BudgetPolicy

## Archetype policies. When non-empty, the cluster pass runs cluster-planned
## BFS-grow using these per-archetype target ratios + size distributions;
## empty leaves every node archetype-less (and content-less).
@export var archetypes: Array[ArchetypePolicy] = []

## Subtype placement (#1056) — the WEIGHTED subtypes only. Each carries its own
## `base_chance`; the default subtype is the remainder and authors none. Empty
## = every node lands on [method resolved_default_subtype]. The roll comes off
## a salted stream ([constant GraphProcgen._SUBTYPE_RNG_SALT]), so authoring or
## retuning one shifts no other node's content. See docs/design/node_subtypes.md.
@export var subtypes: Array[NodeSubtype] = []

## Per-preset override of the global default subtype (D14). `null` =
## [method NodeSubtype.regular].
@export var default_subtype: NodeSubtype = null

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


## The subtype a node lands on when it rolls nothing — and when what it rolled
## has no drawable content (D13's demotion). Never null.
func resolved_default_subtype() -> NodeSubtype:
	return default_subtype if default_subtype != null else NodeSubtype.regular()


## Every [ScalarField] this module holds, across all its holders — what
## generation hands the resolved mask radius to. `guaranteed_placements` is an
## untyped Resource array (see above), hence the duck-typed guard.
func scalar_fields() -> Array[ScalarField]:
	var out: Array[ScalarField] = []
	if budget_policy != null:
		out.append_array(budget_policy.scalar_fields())
	for p in guaranteed_placements:
		if p != null and p.has_method("scalar_fields"):
			out.append_array(p.scalar_fields())
	return out
