@tool
class_name ProcgenAddonDraw
extends RefCounted

## The post-loop addon pass of [method GraphProcgen.generate] (hub #422,
## child 1), extracted from `graph_procgen.gd` with its body unchanged.
## Static and stateless — the caller derives the salted stream
## (`GraphProcgen._ADDON_RNG_SALT`) and hands it in, owns the draw order and
## emits progress itself; this phase never touches the callback. Same seed →
## byte-identical graph is guarded by
## `test/integration/procgen/test_procgen_golden.gd`.


## Places `roundi(node_count × k / 100)` addons, each on a node drawn
## uniformly WITH replacement from `eligible`. A repeat draw raises the node's
## `stake_level` to its new addon count BEFORE the attach, so `addon count ≤
## addon_slots` holds after every step and a node's stake always equals its
## addon count. A draw landing on a node at `max_addons_per_node`, or whose
## remaining legal pool is empty (unique filter), is redrawn; redraws are
## bounded at 4× the target so the pass always ends — it falls short only when
## the pool is exhausted.
static func run(
		eligible: Array[SkillNode],
		node_count: int,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> void:
	var policy: AddonPolicy = config.content.addon_policy if config.content != null else null
	if policy == null or policy.pool == null or eligible.is_empty():
		return
	var target := roundi(float(node_count) * policy.addons_per_100_nodes / 100.0)
	var max_attempts := target * 4
	# Per-node ledger (eligible index → count / minted unique scenes): an addon
	# instance does not carry its pool entry's scene, the uniqueness key.
	var counts: Dictionary = {}
	var minted_unique: Dictionary = {}
	var placed := 0
	var attempts := 0
	while placed < target and attempts < max_attempts:
		attempts += 1
		var idx := rng.randi_range(0, eligible.size() - 1)
		var count: int = counts.get(idx, 0)
		if count >= policy.max_addons_per_node:
			continue
		var minted: Array = minted_unique.get(idx, [])
		var entry := weighted_pick(policy.pool, minted, rng)
		if entry == null:
			continue
		var instance: SkillNodeAddon = entry.mint(rng)
		if instance == null:
			continue
		var sn := eligible[idx]
		count += 1
		if count > 1:
			EntityFactory.set_procgen_stake(sn, count)
		sn.add_child(instance)
		counts[idx] = count
		if instance.unique:
			minted.append(entry.addon_scene)
			minted_unique[idx] = minted
		placed += 1


static func weighted_pick(
		pool: AddonPool,
		minted_unique_scenes: Array,
		rng: RandomNumberGenerator,
) -> AddonPoolEntry:
	var total := 0.0
	for e in pool.entries:
		if e == null or e.weight <= 0.0 or e.addon_scene == null:
			continue
		if e.addon_scene in minted_unique_scenes:
			continue
		total += e.weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in pool.entries:
		if e == null or e.weight <= 0.0 or e.addon_scene == null:
			continue
		if e.addon_scene in minted_unique_scenes:
			continue
		r -= e.weight
		if r <= 0.0:
			return e
	return null


