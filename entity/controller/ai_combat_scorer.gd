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
## every other tier-gated term; melee (slice C) is the first real source of a
## nonzero [param thinned_nodes] into [method score].
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
static func expected_damage(outcome: AttackOutcome) -> float:
	if outcome == null:
		return 0.0
	var total := 0.0
	for hit in outcome.hits:
		total += Mitigation.apply(hit, hit.target)
	return total


## Score one resolved candidate. [param thinned_nodes] is the count of the
## attacker's own nodes this candidate would cost to execute (0 for ranged/
## magic, which never reshape the attacker's own territory; melee passes the
## induced-subgraph size that would be spent).
static func score(mode: BattleSystem.AttackMode, outcome: AttackOutcome, target: SkillNode,
		attacker: Entity, ai_tier: int, thinned_nodes: int = 0) -> ScoredCandidate:
	var c := ScoredCandidate.new()
	c.mode = mode
	c.target = target
	c.outcome = outcome
	c.ev = expected_damage(outcome)
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


## Heuristic score for a candidate frontier allocation (unowned node adjacent
## to the attacker's territory), given the enemies currently visible. Higher
## is better. Two components:
##   - directional: closer to the nearest visible enemy scores higher (a
##     frontier pick that grows toward the fight beats one that grows away
##     from it).
##   - tactical-enable: if allocating this candidate would put a new firing
##     position in range of a target that's currently a NEAR MISS (the
##     attacker's existing leaves fall just short of a kill), that dominates
##     distance entirely — see [constant _NEAR_MISS_ENABLE_BONUS].
## Returns 0.0 if [param candidate] is out of range of every visible enemy
## and there is nothing to enable or move toward.
static func score_frontier(candidate: SkillNode, attacker: Entity,
		visible_enemies: Array[SkillNode]) -> float:
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
		var current_hp := target.get_current_hp()
		if current_hp <= 0.0:
			continue
		var current_ev := _current_ranged_ev(attacker, target)
		if current_ev >= current_hp:
			continue # already lethal without this candidate — nothing to enable
		var per_shot: float = float(attacker.stat_board.ranged_damage.value) \
				if attacker.stat_board.ranged_damage != null else 1.0
		if current_hp - current_ev <= maxf(per_shot, 1.0):
			enable_bonus = maxf(enable_bonus, _NEAR_MISS_ENABLE_BONUS)
	if nearest_distance == INF:
		return 0.0
	return enable_bonus - nearest_distance


## Current best ranged EV against [param target] using the attacker's
## EXISTING owned leaves — the baseline [method score_frontier] checks a
## candidate allocation against to detect a near miss.
static func _current_ranged_ev(attacker: Entity, target: SkillNode) -> float:
	var plan := RangedAttackPlan.new()
	plan.attacker = attacker
	plan.target = target
	if not plan.is_valid():
		return 0.0
	return expected_damage(plan.resolve())
