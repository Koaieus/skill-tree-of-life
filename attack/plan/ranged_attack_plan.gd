class_name RangedAttackPlan
extends AttackPlan

## Single-target ranged attack: the player left-clicks an enemy-occupied
## node to mark it as the target (left-click a different hostile node to
## retarget directly — there's no separate origin step to pop first).
## Firing positions are derived (every leaf of the attacker's owned
## territory). Each leaf reads its own `range` stat (node-local via
## [member SkillNode.node_board], so per-node modifiers can extend reach);
## leaves whose range reaches the target light up as ORIGIN. Right-click
## pops the target — see docs/design/click_grammar.md.

var target: SkillNode = null


## One entry of the authored firing schedule (see [method get_firing_schedule]).
## `target` is carried explicitly alongside `firing_node` — redundant today
## since ranged is single-target, but it makes the list a self-describing
## wire payload rather than one that needs a side-channel target, per the
## issue's "Explicit firing list" section. `distance` is carried for the same
## reason, and because the ramp is metric now: [method resolve] maps it to a
## launch time directly, so recomputing it there (after the sort already
## computed it twice per comparison) would be a third derivation of the same
## number.
class FiringShot:
	var firing_node: SkillNode
	var target: SkillNode
	var distance: float

	func _init(p_firing_node: SkillNode, p_target: SkillNode) -> void:
		firing_node = p_firing_node
		target = p_target
		distance = p_firing_node.global_position.distance_to(p_target.global_position)


func _init() -> void:
	mode = BattleSystem.AttackMode.RANGED


## Wire form: the base fields plus the single target id. Firing positions are
## DERIVED (every reaching leaf of the attacker's territory), so they are not
## wire state — a peer rebuilding this plan re-derives the same schedule from
## the same world.
func to_dict(graph: Graph) -> Dictionary:
	var d := super(graph)
	d["target"] = graph.get_stable_id(target) if graph != null and target != null else 0
	return d


static func from_dict(d: Dictionary, graph: Graph) -> RangedAttackPlan:
	var plan := RangedAttackPlan.new()
	plan._read_base(d, graph)
	plan.target = graph.get_by_stable_id(int(d.get("target", 0))) if graph != null else null
	return plan


func _on_node_left_clicked(node: SkillNode) -> void:
	if not _is_valid_target(node):
		return
	if target == node:
		return
	target = node
	state_changed.emit()


func pop() -> bool:
	if target == null:
		return false
	reset()
	return true


func reset() -> void:
	if target == null:
		return
	target = null
	state_changed.emit()


func get_firing_positions() -> Array[SkillNode]:
	if attacker == null or attacker.navigator == null:
		return []
	return attacker.navigator.get_leaf_nodes()


## Subset of [method get_firing_positions] whose per-leaf [code]range[/code]
## stat reaches the current target. Empty if no target. Append order comes
## from [method get_firing_positions] (graph mirror insertion order, i.e.
## allocation order) — callers that care about firing/arrival ORDER must use
## [method get_firing_schedule] instead; this stays around for highlighting
## and validation, which are order-agnostic.
func get_reaching_firing_positions() -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	if target == null:
		return result
	for leaf in get_firing_positions():
		if leaf.global_position.distance_to(target.global_position) <= _leaf_range(leaf):
			result.append(leaf)
	return result


## The authored, ordered firing list — the ordering authority for
## [method resolve] (docs/domain/attack-timeline.md "The ranged volley
## ramp"), and (via [member FiringShot.distance]) its timing authority too.
## Ranked by euclidean distance to target, ascending; ties broken by
## [member SkillNode.stable_id] (wire-legal, minted by Graph — never
## allocation/mirror-insertion order, which is the bug this issue fixes:
## allocation order must never influence combat outcome). Empty if no target.
func get_firing_schedule() -> Array[FiringShot]:
	var result: Array[FiringShot] = []
	if target == null:
		return result
	var ranked := get_reaching_firing_positions()
	ranked.sort_custom(_ranks_before)
	for firing in ranked:
		result.append(FiringShot.new(firing, target))
	return result


func _ranks_before(a: SkillNode, b: SkillNode) -> bool:
	var da := a.global_position.distance_to(target.global_position)
	var db := b.global_position.distance_to(target.global_position)
	# Exact comparison, not is_equal_approx — an approximate tie test is not
	# transitive and breaks the strict weak ordering sort_custom requires.
	# It also buys nothing: two leaves genuinely equidistant from the target
	# produce bit-identical distances here, so they still fall through to the
	# stable_id tiebreak.
	if da != db:
		return da < db
	return a.stable_id < b.stable_id


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null or attacker == null:
		return HighlightRole.NONE
	if target != null and node == target:
		return HighlightRole.HOSTILE_TARGET
	if node.owned_by == attacker:
		if get_firing_positions().has(node) and target != null:
			var d := node.global_position.distance_to(target.global_position)
			return HighlightRole.ORIGIN if d <= _leaf_range(node) else HighlightRole.NONE
		return HighlightRole.NONE
	if node.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE:
		return HighlightRole.IN_RANGE
	return HighlightRole.NONE


func get_node_range(node: SkillNode) -> float:
	if attacker == null or attacker.navigator == null:
		return 0.0
	if get_firing_positions().has(node):
		return _leaf_range(node)
	return 0.0


func _leaf_range(node: SkillNode) -> float:
	var v: Variant = node.get_local_value(&"range")
	return float(v) if v != null else 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if target == null:
		errors.append(&'No target')
		return errors
	if target.ownership_bit(attacker) != SkillNode.Ownership.HOSTILE:
		errors.append(&'Target node is not owned by an enemy')
	if get_reaching_firing_positions().is_empty():
		errors.append(&'No firing position can reach target')
	return errors


func _is_valid_target(node: SkillNode) -> bool:
	if node == null or attacker == null:
		return false
	return node.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE


func resolve_against(world: CombatWorld) -> AttackOutcome:
	# One DamageInstance per scheduled shot, in the authored firing order
	# (see get_firing_schedule) — flat-armour-friendly, stagger-VFX-friendly.
	# Each hit's arrival_time is authored from where the firing leaf sits in
	# the volley's own DISTANCE SPAN — never from append order, and never from
	# distance/speed (flight time stays constant):
	#   frac         = (distance - d_min) / (d_max - d_min)   # 0 .. 1
	#   launch_time  = DRAW_TIME + frac * TOTAL_STAGGER
	#   arrival_time = launch_time + FLIGHT_TIME (constant)
	# so the recorded timeline is the ordering authority OutcomeApplier reads
	# (docs/domain/attack-timeline.md "The ranged volley ramp").
	#
	# The ramp is METRIC, not ordinal (it used to lerp on rank / (n - 1)):
	# two leaves 0.1px apart now launch 0.1px apart in the span rather than a
	# full 1/(n-1) slice apart, so a clustered firing line reads as one salvo
	# and a lone outlier owns the whole tail. Allocation order still cannot
	# influence it — distance is pure geometry off `global_position`.
	var outcome := AttackOutcome.new()
	outcome.resolve_seed = resolve_seed
	if not is_valid():
		return outcome
	var schedule := get_firing_schedule()
	var n := schedule.size()
	# schedule is sorted by distance ascending, so the span's ends are its ends.
	var d_min: float = schedule[0].distance if n > 0 else 0.0
	var span: float = (schedule[n - 1].distance - d_min) if n > 0 else 0.0
	for rank_i in n:
		var shot: FiringShot = schedule[rank_i]
		var hit := RangedDamageFormula.compute(attacker, shot.firing_node, shot.target)
		hit.source = self
		# Exact `<= 0.0`, not is_equal_approx: this guards a DIVISION, and a
		# degenerate span is exactly the n == 1 / all-equidistant case, where
		# every shot legitimately launches on the same beat. Dividing anyway
		# would stamp NaN into arrival_time — which flows through the VFX
		# `maxf` and the applier's BeatClock as garbage, with no error.
		var frac: float = 0.0 if span <= 0.0 else (shot.distance - d_min) / span
		var launch_time: float = RangedDamageFormula.DRAW_TIME \
				+ frac * RangedDamageFormula.TOTAL_STAGGER
		hit.arrival_time = launch_time + RangedDamageFormula.FLIGHT_TIME
		outcome.hits.append(hit)
	# Every arrow rolls its own crit (#507 — owner call: "a hit can crit"), off
	# the stamped seed, never `randf()`. A 40-leaf empire therefore rolls 40
	# times against one node; that is more chances for more shots, which is
	# what a hit-based crit model means, and it was settled as intended rather
	# than a problem to design around.
	CritRoll.decide_all(outcome, CritRoll.stream_for(resolve_seed))
	# Ranged selects on pure geometry, so nothing above read `world` at all —
	# every live read it makes is inside `RangedHitInstance.land_on`, which is
	# what this pass runs. Un-awaited on purpose: the default clock is
	# [method BeatClock.instant_clock], which never parks, so `apply` runs to
	# completion synchronously and `resolve_against` stays a plain function.
	# (Awaiting would make every `resolve()` caller a coroutine.)
	OutcomeApplier.apply(outcome, world)
	return outcome
