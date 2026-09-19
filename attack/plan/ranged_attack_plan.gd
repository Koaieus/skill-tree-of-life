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
## Composition (#957): `{type_id: n}` — N is the sum, each count ≤ its
## quiver bin. EMPTY means the bare default, resolved live by
## [method effective_ammo_counts]: N = [method max_n], all base arrows. The
## tray (#954) writes an explicit dict; the wire always carries the explicit
## one ([method to_dict]), so a mirror never re-derives a default.
var ammo_counts: Dictionary = {}

const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

const ERR_NO_AMMO := &'No arrows in the quiver'
const ERR_NO_SHOTS := &'No firing leaf in range has shots left'
const ERR_VOLLEY_LIMIT := &'Volley limit reached this turn'


## The quiver this plan draws from, or null on a board without one.
func _quiver() -> Quiver:
	if attacker == null or attacker.stat_board == null:
		return null
	return attacker.stat_board.arrows as Quiver


## Σ [method SkillNode.shots_left] over the reaching leaves — the per-turn
## shot budget this volley can spend (#956).
func _shots_available() -> int:
	var total := 0
	for leaf in get_reaching_firing_positions():
		total += leaf.shots_left()
	return total


## Owner (2026-09-18): `max N = min(arrows.current, Σ shots_left over leaves
## in range)`.
func max_n() -> int:
	var quiver := _quiver()
	var stock: int = roundi(quiver.current) if quiver != null else 0
	return mini(stock, _shots_available())


## The composition actually fired: [member ammo_counts] when set, else the
## bare default — N = max, every arrow the base type (capped by its bin, so
## a quiver holding only specials yields an empty default and validate's
## no-ammo state rather than a volley of the wrong type).
func effective_ammo_counts() -> Dictionary:
	if not ammo_counts.is_empty():
		return ammo_counts
	var quiver := _quiver()
	if quiver == null:
		return {}
	var base_n := mini(max_n(), quiver.stock_of(AmmoTypeRoster.BASE_ID))
	return {AmmoTypeRoster.BASE_ID: base_n} if base_n > 0 else {}


## Arrows in this volley — the sum of [method effective_ammo_counts].
func n() -> int:
	var total := 0
	for count in effective_ammo_counts().values():
		total += int(count)
	return total


## The volley's ammo, one [AmmoType] per shot, in roster `order` — the order
## the schedule assigns them along. Owner: *"5 armor breaker shots configured
## first -> will land first, regardless of what wave inside the burst they
## launch at"*. Unknown ids are skipped (validate refuses them anyway).
func _ammo_sequence() -> Array[AmmoType]:
	var seq: Array[AmmoType] = []
	var counts := effective_ammo_counts()
	for t in _ROSTER.sorted():
		for _i in int(counts.get(t.id, 0)):
			seq.append(t)
	return seq


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
	var wave: int = 0
	var ammo_type: AmmoType = null

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
	# The EFFECTIVE counts, never the raw field: a bare-default authority
	# holds an empty dict and its mirror must fire the same explicit volley.
	var counts := {}
	for id in effective_ammo_counts():
		counts[String(id)] = int(effective_ammo_counts()[id])
	d["ammo_counts"] = counts
	return d


static func from_dict(d: Dictionary, graph: Graph) -> RangedAttackPlan:
	var plan := RangedAttackPlan.new()
	plan._read_base(d, graph)
	plan.target = graph.get_by_stable_id(int(d.get("target", 0))) if graph != null else null
	var counts: Dictionary = d.get("ammo_counts", {})
	for id in counts:
		plan.ammo_counts[StringName(id)] = int(counts[id])
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
##
## WAVE-MAJOR (#957, owner 2026-09-18): each wave, every reaching leaf with a
## shot left fires one arrow, nearest-first — ranked by euclidean distance to
## target, ties broken by [member SkillNode.stable_id] (wire-legal, minted by
## Graph — never allocation/mirror-insertion order: allocation order must
## never influence combat outcome). Waves repeat until N (3 leaves at 5/5,
## 5/5, 4/5 → waves of 3, 3, 3, 3, 2). Ammo types are assigned along that
## order in roster `order` — the first shots of wave 0 carry the specials.
## Empty if no target or N is 0.
func get_firing_schedule() -> Array[FiringShot]:
	var result: Array[FiringShot] = []
	if target == null:
		return result
	var ranked := get_reaching_firing_positions()
	ranked.sort_custom(_ranks_before)
	var ammo := _ammo_sequence()
	var remaining := ammo.size()
	var fired: Dictionary[SkillNode, int] = {}
	var wave := 0
	while remaining > 0:
		var fired_this_wave := 0
		for leaf in ranked:
			if remaining <= 0:
				break
			if fired.get(leaf, 0) >= leaf.shots_left():
				continue
			var shot := FiringShot.new(leaf, target)
			shot.wave = wave
			shot.ammo_type = ammo[ammo.size() - remaining]
			result.append(shot)
			fired[leaf] = fired.get(leaf, 0) + 1
			fired_this_wave += 1
			remaining -= 1
		if fired_this_wave == 0:
			# Budget exhausted below N (validate refuses this; the guard keeps
			# a stale plan from spinning).
			break
		wave += 1
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
	# The third state (#957): a volley needs shots left on a reaching leaf,
	# arrows to fire, and a volley slot this turn.
	if _shots_available() <= 0:
		errors.append(ERR_NO_SHOTS)
	var quiver := _quiver()
	if quiver == null or roundi(quiver.current) <= 0:
		errors.append(ERR_NO_AMMO)
	if attacker.stat_board != null and attacker.stat_board.volleys_per_turn != null \
			and attacker.volleys_launched_this_turn >= int(attacker.stat_board.volleys_per_turn.value):
		errors.append(ERR_VOLLEY_LIMIT)
	if not errors.is_empty():
		return errors
	var counts := effective_ammo_counts()
	var total := 0
	for id in counts:
		var count := int(counts[id])
		if _ROSTER.by_id(id) == null:
			errors.append(&'Unknown ammo type: %s' % id)
		elif count > quiver.stock_of(id):
			errors.append(&'Not enough %s arrows (%d < %d)' % [id, quiver.stock_of(id), count])
		total += count
	if total <= 0:
		errors.append(&'Volley is empty')
	elif total > _shots_available():
		errors.append(&'Volley exceeds the shots left on reaching leaves (%d > %d)' % [total, _shots_available()])
	return errors


func _is_valid_target(node: SkillNode) -> bool:
	if node == null or attacker == null:
		return false
	return node.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE


func resolve_against(world: CombatWorld) -> AttackOutcome:
	# One DamageInstance per scheduled shot, in the authored firing order
	# (see get_firing_schedule) — flat-armour-friendly, stagger-VFX-friendly.
	# Each hit's STRUCTURAL KEY is where the firing leaf sits in the volley's
	# own DISTANCE SPAN — never append order, and never distance/speed:
	#   frac = (distance - d_min) / (d_max - d_min)   # 0 .. 1
	# and that is the whole of what this plan records about timing (#543). The
	# seconds it used to stamp —
	# `DRAW_TIME + frac * TOTAL_STAGGER + FLIGHT_TIME` — are now
	# [constant ScheduleEntry.Cadence.RAMP] arithmetic inside
	# [method OutcomeSchedule.compile], reading
	# [member PresentationTempo.volley_stagger_span] and friends, so a
	# slow-motion replay stretches the ramp instead of re-authoring it.
	# The compiled schedule is still the ordering authority OutcomeApplier reads
	# (docs/domain/attack-timeline.md "The ranged volley ramp").
	#
	# The ramp is METRIC, not ordinal (it used to lerp on rank / (n - 1)):
	# two leaves 0.1px apart now launch 0.1px apart in the span rather than a
	# full 1/(n-1) slice apart, so a clustered firing line reads as one salvo
	# and a lone outlier owns the whole tail. Allocation order still cannot
	# influence it — distance is pure geometry off `global_position`.
	#
	# WAVES (#957): the volley is wave-major (see get_firing_schedule) and one
	# volley is ONE ramp — waves sit back-to-back inside it and
	# `volley_draw_time` is paid once. The key therefore encodes both:
	#   key = (wave + frac) / waves
	# with frac over the volley's whole distance span, so it stays in [0, 1]
	# (the RAMP branch's assumption) and collapses to plain frac for a
	# single wave. The last shot of wave k and the first of wave k+1 share a
	# key; the schedule's (structural_key, original_index) sort keeps them in
	# wave order, they just land on one beat.
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.RAMP
	outcome.resolve_seed = resolve_seed
	# Owner (2026-09-18): "Firing costs 0 AP" — the volley economy is arrows
	# and per-leaf shots, both consumed by BattleSystem._commit.
	outcome.ap_cost = 0
	if not is_valid():
		return outcome
	var schedule := get_firing_schedule()
	var shot_count := schedule.size()
	var d_min: float = INF
	var d_max: float = -INF
	var waves := 0
	for shot in schedule:
		d_min = minf(d_min, shot.distance)
		d_max = maxf(d_max, shot.distance)
		waves = maxi(waves, shot.wave + 1)
	var span: float = (d_max - d_min) if shot_count > 0 else 0.0
	for rank_i in shot_count:
		var shot: FiringShot = schedule[rank_i]
		var hit := RangedDamageFormula.compute(attacker, shot.firing_node, shot.target, shot.ammo_type)
		hit.source = self
		# Exact `<= 0.0`, not is_equal_approx: this guards a DIVISION, and a
		# degenerate span is exactly the n == 1 / all-equidistant case, where
		# every shot legitimately launches on the same beat. Dividing anyway
		# would stamp NaN into the structural key — which flows through the
		# compiler into every second, and through the applier's BeatClock as
		# garbage, with no error.
		var frac: float = 0.0 if span <= 0.0 else (shot.distance - d_min) / span
		hit.structural_key = (float(shot.wave) + frac) / float(maxi(waves, 1))
		outcome.hits.append(hit)
		# A typed arrow's status (#495) is a second hit for the same landing —
		# same key, appended right after, so it lands on the arrow's beat and
		# after the arrow (the schedule's original-index tiebreak).
		var status := RangedDamageFormula.status_for(hit)
		if status != null:
			outcome.hits.append(status)
	# Seconds, once, before anything consumes an order: `decide_all` below
	# draws its seeded stream in landing order, which is the schedule's.
	outcome.schedule = OutcomeSchedule.compile(outcome)
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
