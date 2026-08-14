@tool
class_name GraphProcgenSpellGrants
extends RefCounted

## Two-stage spell-grant distribution (#206, widened). #206's original v1 was
## a per-node independent Bernoulli roll — no coverage guarantee, so a
## low-weight spell could land zero copies on the whole level. That starved
## LootSystem's #204 spell draft of anything to offer (every entity shares
## the same starter spellbook, so the only route to a genuinely new spell is
## looting one an NPC picked up — see the #204 issue thread). Replaced with a
## two-stage draw: decide how many copies of EACH pool entry the level gets
## (a Poisson roll around a weighted share of the level's total grant budget,
## floored at 1 — every spell in the pool is guaranteed to appear), then
## place those copies on distinct INT-archetype nodes. A node CAN end up
## hosting more than one different SpellGrant if two spells' placements
## collide — [EmblemResolver.Resolution.carve_ties] already anticipates
## multiple SPELL-priority carves competing on one node; the combine
## strategy for rendering that lives in the renderer, not here.
##
## v1 scope: gated to INT-archetype nodes only (spells are INT-flavoured).
## `ratio` reads as "fraction of INT nodes expected to carry a grant" (1.0 =
## one grant per INT node on average; 0.5 = half as many) — the level's total
## grant budget is `ratio * int_nodes.size()`, split across pool entries by
## weight (same [member SpellGrantPoolEntry.weight] as before, still
## overridable per entry, default 1.0).

const _INT_PRIMARY_STAT := &"intelligence"


## Whether a node with this primary stat is eligible for a spell grant. The
## one place that answers "is this an INT node" — callers building the
## eligible-node list should route through this rather than comparing the
## stringname directly.
static func is_eligible_node(archetype_primary_stat: StringName) -> bool:
	return archetype_primary_stat == _INT_PRIMARY_STAT


## Distributes [SpellGrant]s across [param int_nodes] (nodes the caller has
## already filtered to INT-archetype via [method is_eligible_node]). No-ops
## when `pool` is unset, `ratio` is <= 0, or there are no eligible nodes.
static func distribute(
		int_nodes: Array[SkillNode],
		pool: SpellGrantPool,
		ratio: float,
		rng: RandomNumberGenerator,
) -> void:
	if pool == null or ratio <= 0.0 or int_nodes.is_empty():
		return
	var entries := _weighted_entries(pool)
	if entries.is_empty():
		return

	var total_weight := 0.0
	for e in entries:
		total_weight += e.weight
	var total_budget: float = ratio * int_nodes.size()

	for e in entries:
		var lam: float = total_budget * (e.weight / total_weight)
		var count: int = maxi(1, _poisson(lam, rng))
		_place(e.spell_def, count, int_nodes, rng)


static func _weighted_entries(pool: SpellGrantPool) -> Array[SpellGrantPoolEntry]:
	var out: Array[SpellGrantPoolEntry] = []
	for e in pool.entries:
		if e != null and e.spell_def != null and e.weight > 0.0:
			out.append(e)
	return out


## Knuth's algorithm — fine at the small lambdas a per-spell share of a
## level's grant budget produces.
static func _poisson(lam: float, rng: RandomNumberGenerator) -> int:
	if lam <= 0.0:
		return 0
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= rng.randf()
		if p <= l:
			break
	return k - 1


## Places up to `count` copies of `spell_def` on distinct nodes drawn from
## `int_nodes` — a partial Fisher-Yates (swap-to-front) per call, so each
## spell's own copies never repeat a node, but different spells draw
## independently and CAN collide onto the same node (stacking allowed).
## Clamped to `int_nodes.size()` when `count` exceeds the eligible pool.
static func _place(
		spell_def: SpellDef, count: int, int_nodes: Array[SkillNode], rng: RandomNumberGenerator
) -> void:
	var n := int_nodes.size()
	var take := mini(count, n)
	for i in take:
		var j := rng.randi_range(i, n - 1)
		var tmp := int_nodes[i]
		int_nodes[i] = int_nodes[j]
		int_nodes[j] = tmp
		var grant := SpellGrant.new()
		grant.spell_def = spell_def
		print_debug('[PROCGEN] Placed SpellGrant: %s on %s' % [spell_def.name, int_nodes[i].name])
		int_nodes[i].add_effect(grant)
