class_name AiCombatScorer
extends RefCounted

## Shared per-candidate EV scorer for AI v1 (#378 slice B). Ranged and magic
## candidates score through the same pipeline below; melee (slice C) is
## expected to route through [method score] too once [code]ai_blade_rollout.gd
## [/code] builds [MeleeAttackPlan] candidates — the scorer only needs an
## already-[method AttackPlan.resolve]d [AttackOutcome], so it doesn't care
## which plan class produced it.
##
## Damage numbers are read off the SAME preview path [BattleSystem.launch_attack]
## commits through — [method AttackPlan.resolve] (pure) + [Mitigation.apply]
## (the same post-armor formula [SkillNode.take_damage] runs) — so a scored
## candidate's expected damage never diverges from what executing it actually
## deals. Never hand-roll a second damage estimate here.
##
## Bonus/penalty terms are tier-gated via a single int on the controller
## ([member AIController.ai_tier]) — see the class doc there. At
## [code]ai_tier == 0[/code] every term below except [member ScoredCandidate.kill_bonus]
## is zero, so candidates rank on raw EV (+ kill preference) alone.

const _KILL_BONUS := 1000.0
const _CUT_VERTEX_WEIGHT := 25.0
const _ENEMY_WEAK_WEIGHT := 5.0
## SP-turns lost per thinned node (wound now, heals ~1/turn — see
## [member SkillPointStat.wound]). Scaled by [member AIController.ai_tier] like
## every other tier-gated term; melee (slice C, [AiBladeRollout]) is the first
## real source of a nonzero [param thinned_nodes] into [method score] — a real
## defensive-spike pop count, not the blade's node-selection size.
const _SHAPE_RISK_WEIGHT := 10.0
## Distance-dominating bonus so a tactical-enabling frontier pick always beats
## a merely-closer one — see [method score_frontier].
const _NEAR_MISS_ENABLE_BONUS := 1.0e6


## One scored attack candidate. A small breakdown, not a bare float — lets
## [member AIController.debug_trace] print WHY a candidate won, keeps the
## tier-gating tests honest (assert a term is exactly 0.0 at tier 0 rather
## than reverse-engineering it from the total), and is the seam the swarmify
## addendum's future `AiWeights` multiply-in slots into per term.
class ScoredCandidate:
	var mode: BattleSystem.AttackMode = BattleSystem.AttackMode.NONE
	var target: SkillNode = null
	## Casting source for MAGIC candidates; unused (null) for RANGED.
	var source_node: SkillNode = null
	## Spell for MAGIC candidates; unused (null) for RANGED.
	var spell: SpellDef = null
	## Blade member selection for MELEE candidates; empty for RANGED/MAGIC.
	var blade_nodes: Array[SkillNode] = []
	var outcome: AttackOutcome = null

	var ev: float = 0.0
	var is_kill: bool = false
	var kill_bonus: float = 0.0
	var cut_vertex_bonus: float = 0.0
	var enemy_weak_bonus: float = 0.0
	var self_shape_risk: float = 0.0
	var total: float = 0.0
	var trace: String = ""

	func _to_string() -> String:
		return trace


## Expected damage this outcome would deal on commit — post-mitigation, summed
## across every hit, via the exact formula [SkillNode.take_damage] applies.
## Filters to [method AttackOutcome.damage_hits] (#381) — [Mitigation.apply]
## takes a [DamageInstance] specifically, and a heal shouldn't score as damage.
##
## With [param attacker] supplied, hits on nodes that aren't AI targets
## ([method AiRecon.is_ai_target] — dormant-core blockers) contribute nothing.
## An AoE or blade that clips a blocker must not bank EV for it, or the AI
## still steers into scenery even though the target *list* excludes it.
## Defaults to null (count every hit) so a test scoring a bare outcome with no
## attacker context reads the raw sum.
static func expected_damage(outcome: AttackOutcome, attacker: Entity = null) -> float:
	if outcome == null:
		return 0.0
	var total := 0.0
	for hit in outcome.damage_hits():
		if attacker != null and not AiRecon.is_ai_target(attacker, hit.target):
			continue
		total += Mitigation.apply(hit, hit.target)
	return total


## Score one resolved candidate. [param thinned_nodes] is the count of the
## attacker's own blade vertices this candidate ACTUALLY lost executing (0 for
## ranged/magic, which never reshape the attacker's own territory). Merely
## selecting nodes for a blade doesn't wound them — only a defender's
## defensive-spike pop does (see [BladePopResolver]) — so melee (slice C)
## passes [member AttackOutcome.thinned_nodes] (the real per-swing pop count
## [MeleeAttackPlan.resolve] already computes), not blade_nodes.size().
static func score(mode: BattleSystem.AttackMode, outcome: AttackOutcome, target: SkillNode,
		attacker: Entity, ai_tier: int, thinned_nodes: int = 0) -> ScoredCandidate:
	var c := ScoredCandidate.new()
	c.mode = mode
	c.target = target
	c.outcome = outcome
	c.ev = expected_damage(outcome, attacker)
	var target_hp: float = target.get_current_hp() if target != null else 0.0
	c.is_kill = target_hp > 0.0 and c.ev >= target_hp
	c.kill_bonus = _KILL_BONUS if c.is_kill else 0.0
	if ai_tier > 0:
		if _is_cut_vertex(target):
			c.cut_vertex_bonus = _CUT_VERTEX_WEIGHT * ai_tier
		c.enemy_weak_bonus = _armor_weakness(target) * _ENEMY_WEAK_WEIGHT * ai_tier
		c.self_shape_risk = float(thinned_nodes) * _SHAPE_RISK_WEIGHT * ai_tier
	c.total = c.ev + c.kill_bonus + c.cut_vertex_bonus + c.enemy_weak_bonus - c.self_shape_risk
	c.trace = "[%s→%s] ev=%.1f kill=%s cut=%.1f weak=%.1f risk=%.1f total=%.1f" % [
		BattleSystem.AttackMode.keys()[mode],
		target.name if target != null else "?",
		c.ev, ("yes" if c.is_kill else "no"),
		c.cut_vertex_bonus, c.enemy_weak_bonus, c.self_shape_risk, c.total]
	return c


## Highest-[member ScoredCandidate.total] entry, or null if [param candidates]
## is empty. Ties keep the first entry (stable — callers build candidates in a
## deterministic order).
static func pick_best(candidates: Array[ScoredCandidate]) -> ScoredCandidate:
	var best: ScoredCandidate = null
	for c in candidates:
		if best == null or c.total > best.total:
			best = c
	return best


## True if [param target] is a cut vertex within ITS OWNER's territory — i.e.
## a high-value strike: depleting it islands part of the enemy's shape. Offence
## reads the same [method GraphMirror.would_disconnect_from] AiRecon uses
## defensively (one rule, two callers).
static func _is_cut_vertex(target: SkillNode) -> bool:
	if target == null:
		return false
	var owner: Entity = target.owned_by
	if owner == null or owner.navigator == null or owner.core_location == null:
		return false
	if target == owner.core_location:
		return false
	return owner.navigator.would_disconnect_from(target, owner.core_location)


## Negative/low armor reads as a defensive weak point. Armor defaults to 0
## (see stats_system/defs/armor.tres), so this is 0 for an unmodified node and
## only kicks in once something (a debuff, a battlefield event) drives armor
## below baseline.
static func _armor_weakness(target: SkillNode) -> float:
	if target == null:
		return 0.0
	return maxf(0.0, -float(target.get_local_value(&"armor")))


## Which currently-visible enemies are a NEAR MISS for the attacker's
## EXISTING ranged reach — hp survives current owned-leaf EV by no more than
## one more shot. Compute ONCE per turn (the caller passes the result into
## every [method score_frontier] call over the frontier candidate set) rather
## than once per (candidate × target): the graph.md rule against O(N) reach
## queries in a loop applies here too — a [RangedAttackPlan] build + resolve
## per target is a real traversal, and a frontier pass is O(candidates), not
## O(1).
static func near_miss_targets(attacker: Entity, visible_enemies: Array[SkillNode]) -> Dictionary[SkillNode, bool]:
	var out: Dictionary[SkillNode, bool] = {}
	if attacker == null or attacker.stat_board == null:
		return out
	var per_shot: float = float(attacker.stat_board.ranged_damage.value) \
			if attacker.stat_board.ranged_damage != null else 1.0
	for target in visible_enemies:
		if target == null:
			continue
		var current_hp := target.get_current_hp()
		if current_hp <= 0.0:
			continue
		var plan := RangedAttackPlan.new()
		plan.attacker = attacker
		plan.target = target
		var current_ev := expected_damage(plan.resolve(), attacker) if plan.is_valid() else 0.0
		if current_ev >= current_hp:
			continue # already lethal without any new leaf — nothing to enable
		if current_hp - current_ev <= maxf(per_shot, 1.0):
			out[target] = true
	return out


## Heuristic score for a candidate frontier allocation (unowned node adjacent
## to the attacker's territory), given the enemies currently visible and the
## precomputed [param near_miss] set (see [method near_miss_targets]). Higher
## is better. Two components:
##   - directional: closer to the nearest visible enemy scores higher (a
##     frontier pick that grows toward the fight beats one that grows away
##     from it).
##   - tactical-enable: if allocating this candidate would put a new firing
##     position in range of a near-miss target, that dominates distance
##     entirely — see [constant _NEAR_MISS_ENABLE_BONUS].
## Returns 0.0 if [param candidate] is out of range of every visible enemy
## and there is nothing to enable or move toward.
static func score_frontier(candidate: SkillNode, attacker: Entity,
		visible_enemies: Array[SkillNode], near_miss: Dictionary[SkillNode, bool]) -> float:
	if candidate == null or attacker == null or attacker.stat_board == null \
			or visible_enemies.is_empty():
		return 0.0
	var est_range: float = float(attacker.stat_board.range.value) \
			if attacker.stat_board.range != null else 0.0
	var nearest_distance := INF
	var enable_bonus := 0.0
	for target in visible_enemies:
		if target == null:
			continue
		var d := candidate.global_position.distance_to(target.global_position)
		nearest_distance = minf(nearest_distance, d)
		if d > est_range:
			continue
		if near_miss.has(target):
			enable_bonus = _NEAR_MISS_ENABLE_BONUS
	if nearest_distance == INF:
		return 0.0
	return enable_bonus - nearest_distance
