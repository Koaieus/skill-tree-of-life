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
## issue's "Explicit firing list" section.
class FiringShot:
	var firing_node: SkillNode
	var target: SkillNode

	func _init(p_firing_node: SkillNode, p_target: SkillNode) -> void:
		firing_node = p_firing_node
		target = p_target


func _init() -> void:
	mode = BattleSystem.AttackMode.RANGED


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
## ramp"). Ranked by euclidean distance to target, ascending; ties broken by
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


func resolve() -> AttackOutcome:
	# One DamageInstance per scheduled shot, in the authored firing order
	# (see get_firing_schedule) — flat-armour-friendly, stagger-VFX-friendly.
	# Each hit's arrival_time is authored from its rank, not derived from
	# distance/speed or append order:
	#   launch_time = DRAW_TIME + lerp(0, TOTAL_STAGGER, rank / (n - 1))
	#   arrival_time = launch_time + FLIGHT_TIME (constant)
	# so the recorded timeline is the ordering authority OutcomeApplier reads
	# (docs/domain/attack-timeline.md "The ranged volley ramp").
	var outcome := AttackOutcome.new()
	if not is_valid():
		return outcome
	var schedule := get_firing_schedule()
	var n := schedule.size()
	for rank_i in n:
		var shot: FiringShot = schedule[rank_i]
		var hit := RangedDamageFormula.compute(attacker, shot.firing_node, shot.target)
		hit.source = self
		var launch_time := RangedDamageFormula.DRAW_TIME
		if n > 1:
			launch_time += lerpf(0.0, RangedDamageFormula.TOTAL_STAGGER, float(rank_i) / float(n - 1))
		hit.arrival_time = launch_time + RangedDamageFormula.FLIGHT_TIME
		outcome.hits.append(hit)
	return outcome
