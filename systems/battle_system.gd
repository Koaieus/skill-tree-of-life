@tool
class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

signal attack_plan_changed(plan: AttackPlan)
## Fired once a launch commits (resource checks passed, about to resolve).
## `spell` is the active [MagicAttackPlan]'s spell, null for melee/ranged.
## Consumed by [AnnouncementLayer] (#117, #135) for the mode-tinted CALLOUT FX.
signal attack_launched(mode: AttackMode, spell: SpellDef)
## Fires for both plan swap and plan-internal mutation. Subscribers that
## care about lifecycle (mount per-mode UI) use [signal attack_plan_changed];
## subscribers that care about content (re-paint highlights) use this one.
signal attack_plan_state_changed

## Forced-deallocation cascade about to run. `layers[i]` holds every cascade
## node at BFS graph-distance `i` from the impact node; `layers[0] == [impact]`.
## Emitted BEFORE the synchronous force_deallocate loop so VFX can snapshot
## owner colour + schedule a staggered ripple. See docs/domain/allocation-vfx.md.
signal cascade_started(layers: Array, defender: Entity)

## The currently-selected spell for magic attacks. Updated by the spell-picker
## UI; consumed by [method _new_plan] when constructing a [MagicAttackPlan].
## Null means "use the plan's bundled fallback". Live mutation is supported:
## changing this while a magic plan is active re-equips on the active plan
## via [method MagicAttackPlan.set_spell].
signal selected_spell_changed(spell: SpellDef)
var selected_spell: SpellDef = null:
	set(value):
		if selected_spell == value:
			return
		selected_spell = value
		if attack_plan is MagicAttackPlan:
			(attack_plan as MagicAttackPlan).set_spell(value)
		selected_spell_changed.emit(value)

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
@export var graph: Graph
@export var attack_vfx: AttackVFX
@export var melee_preview: MeleePreview
## #491: plays the recorded reveal timeline — the sole driver of the
## post-attack reveal now.
@export var presentation_player: PresentationPlayer

## Presentation clock (#488): the timeline recorded off this attack's
## synchronous mutation. `presentation_player.play`/`play_instant` (in
## `launch_attack`) is what replays it.
var last_reveal_timeline: RevealTimeline = null


var attack_plan: AttackPlan:
	set(value):
		if attack_plan == value:
			return
		if attack_plan != null and attack_plan.state_changed.is_connected(_on_plan_state_changed):
			attack_plan.state_changed.disconnect(_on_plan_state_changed)
		attack_plan = value
		if attack_plan != null:
			attack_plan.state_changed.connect(_on_plan_state_changed)
		attack_plan_changed.emit(value)
		attack_plan_state_changed.emit()


func _on_plan_state_changed() -> void:
	attack_plan_state_changed.emit()

var attack_mode: AttackMode:
	get(): return attack_plan.mode if attack_plan else AttackMode.NONE

var is_attacking: bool:
	get(): return attack_plan != null

## True while resolve()..VFX-await..AP-deduction is in flight, independent
## of whether attack_plan is still set (#406 — the plan now stays live
## through the melee await so its temp-upgrade addons render correctly).
## The one thing that blocks a second launch_attack() mid-swing.
var is_launching := false

func cancel_attack() -> void:
	if is_attacking and not is_launching:
		_reset()
	else:
		push_warning('Cannot cancel attack: not attacking, or a swing is resolving')


## Clear the active plan's selection state without dropping the plan itself —
## keeps the mode set and any sticky preferences (melee swing_cw, magic spell)
## alive. UI's RESET button routes here.
func reset_plan() -> void:
	if attack_plan != null and not is_launching:
		attack_plan.reset()

## The single choke point that tears a plan down (#406) — always calls
## reset() first, so a plan's attached temp-upgrade addons (real SkillNode
## children, not plan-owned state) are freed no matter which path got here:
## cancel, RESET-adjacent teardown, or post-launch.
func _reset() -> void:
	if attack_plan:
		attack_plan.reset()
		attack_plan = null

func request_attack_mode(mode: AttackMode) -> void:
	if is_launching or attack_mode == mode:
		return
	match mode:
		AttackMode.NONE:    cancel_attack()
		AttackMode.MELEE:   attack_plan = _new_plan(MeleeAttackPlan)
		AttackMode.RANGED:  attack_plan = _new_plan(RangedAttackPlan)
		AttackMode.MAGIC:   attack_plan = _new_plan(MagicAttackPlan)

func _new_plan(plan_class: Script) -> AttackPlan:
	var p: AttackPlan = plan_class.new()
	p.attacker = turn_manager.current_entity
	if p is MagicAttackPlan and selected_spell != null:
		(p as MagicAttackPlan).spell = selected_spell
	if p is MeleeAttackPlan:
		(p as MeleeAttackPlan).swing_cw = next_melee_cw
	return p


## Sticky preference for the next [MeleeAttackPlan]'s [member MeleeAttackPlan.swing_cw].
## Toggled by UI; survives plan resets so the player doesn't re-pick direction
## every time they switch into melee mode.
var next_melee_cw: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_node_depleted.connect(_on_node_depleted)


## Commit the active plan. Three phases:
##   1. resolve() → AttackOutcome (pure, no side-effects on plan/world)
##   2. apply the WHOLE outcome synchronously — hits, heals, and (via
##      SkillNode.take_damage → Events.skill_node_depleted) the forced-dealloc
##      cascade — before any await runs (#474: host-authoritative sync needs
##      world state to be a pure function of the resolved outcome, never of a
##      peer's own animation framerate)
##   3. hand the already-applied outcome to VFX as a PURE OBSERVER — it may
##      read `outcome`/`melee_plan.last_events` to time its playback but must
##      never mutate; then AP/plan cleanup
##
## AP is deducted up front; the plan itself stays live through the whole
## await (#406 — a melee plan's attached temp-upgrade addons must keep
## rendering through the live swing) and is cleared in one place, after.
## `is_launching` — not `attack_plan != null` — is what blocks a second
## launch_attack() call during the await window.
func launch_attack() -> void:
	if not is_attacking or is_launching:
		push_warning("BattleSystem.launch_attack: no plan, or already launching")
		return
	if not attack_plan.is_valid():
		push_warning("BattleSystem.launch_attack: invalid plan: %s" % str(attack_plan.validate()))
		return
	var entity := turn_manager.current_entity if turn_manager != null else null
	if entity == null:
		push_warning("BattleSystem.launch_attack: no current entity")
		return
	var outcome := attack_plan.resolve()
	var board: StatBoard = entity.stat_board
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null and ap_pool.available() < outcome.ap_cost:
		push_warning("BattleSystem.launch_attack: insufficient AP (%d < %d)" \
				% [int(ap_pool.current), outcome.ap_cost])
		return
	var mana_pool: PoolStat = board.mana if board != null else null
	if outcome.mana_cost > 0 and mana_pool != null \
			and mana_pool.available() < outcome.mana_cost:
		push_warning("BattleSystem.launch_attack: insufficient mana (%d < %d)" \
				% [int(mana_pool.current), outcome.mana_cost])
		return
	is_launching = true
	if ap_pool != null:
		ap_pool.deplete(float(outcome.ap_cost))
	if outcome.mana_cost > 0 and mana_pool != null:
		mana_pool.deplete(float(outcome.mana_cost))
	var launched_spell: SpellDef = (attack_plan as MagicAttackPlan).spell if attack_plan is MagicAttackPlan else null
	attack_launched.emit(attack_plan.mode, launched_spell)
	# Costs are already deducted; the plan is still live, so an effect can read
	# its targets. Replaces the issue's `_on_battle_start` — there is no battle.
	if attack_plan.attacker != null:
		attack_plan.attacker.dispatch(&"_on_attack_launched", [attack_plan.mode, launched_spell])
	# World mutation happens here, synchronously, for every mode — before any
	# VFX await starts. Whether attack_vfx/melee_preview is null or live, the
	# resulting world state is identical (#474 acceptance).
	_apply_outcome(outcome)
	# Melee: hand off to the MeleePreview (which has the ghost mounted) for a
	# PURE-ANIMATION replay of the swing already applied above. The plan stays
	# live (attack_plan is NOT cleared) through the whole await — its
	# temp-upgrade addons (#406) must stay attached and rendering through both
	# the ghost preview loop and the actual committed swing. _reset() (which
	# frees them) runs once, after.
	var timeline := last_reveal_timeline
	if attack_plan is MeleeAttackPlan and melee_preview != null:
		var melee_plan: MeleeAttackPlan = attack_plan
		# Sequential, not concurrent: GDScript can't hold a handle to a
		# `-> void` coroutine to await later (attempting it either fails the
		# static "cannot get return value" check or, called dynamically,
		# errors at runtime with "Trying to call an async function without
		# await"). `play`'s own duration (bounded by the recorded timeline,
		# itself bounded by each hit's `arrival_time` / `CASCADE_STEP`) is
		# ordinarily short next to the swing replay, so awaiting it after
		# costs little; termination and correctness matter more here than
		# shaving that overlap.
		await melee_preview.launch(melee_plan)
		if timeline != null and presentation_player != null:
			await presentation_player.play(timeline)
		# is_launching flips false BEFORE _reset() (not after) — _reset()'s
		# attack_plan = null synchronously fires attack_plan_changed, and
		# PlayerInputController's gate-refresh listener reads is_launching
		# the instant that signal fires. Clearing it after would have that
		# listener observe a stale "still launching" and never re-enable
		# AttackModeBar.
		is_launching = false
		_reset()
		return
	var coord_scene: PackedScene = null
	if attack_plan is MagicAttackPlan:
		var magic_plan: MagicAttackPlan = attack_plan
		if magic_plan.spell != null:
			coord_scene = magic_plan.spell.vfx_coordinator_scene
	if attack_vfx != null:
		if coord_scene != null:
			await attack_vfx.play(coord_scene, outcome)
		else:
			await attack_vfx.play_ranged_volley(outcome)
		# See the melee branch above for why this runs after, not alongside.
		if timeline != null and presentation_player != null:
			await presentation_player.play(timeline)
	elif timeline != null and presentation_player != null:
		# Headless / no VFX mounted: nothing will ever emit the
		# damage_shown reveals a coordinator would — apply the whole
		# timeline at once instead of waiting on them forever.
		presentation_player.play_instant(timeline)
	is_launching = false
	_reset()


## The one place world mutation happens for an attack: every hit in
## [member AttackOutcome.hits] lands via [OutcomeApplier] — which, via
## take_damage → Events.skill_node_depleted → _on_node_depleted (both
## synchronous), also runs the forced-dealloc cascade. VFX never calls this;
## it only replays what already landed. See the class-level VFX note.
##
## Presentation clock (#491): [OutcomeApplier] records the reveal timeline
## as it mutates; `PresentationPlayer.play`/`play_instant` (wired in
## `launch_attack`) is what replays it.
func _apply_outcome(outcome: AttackOutcome) -> void:
	RevealRecorder.begin(RevealTimeline.new())
	OutcomeApplier.apply(outcome)
	last_reveal_timeline = RevealRecorder.end()


## Forced-deallocation cascade. Runs when a (non-core) node hits 0 HP: the
## depleted node and every node disconnected from the defender's core when
## it leaves are force-dealloc'd. Each cascaded node costs the defender:
##   * 1 wounded SP — currency exchange (invested SP → wounded, reserves a
##     slot in the pool until healed, mirrors PoE mana reservation).
##   * `dealloc_damage` HP off the entity's `health` pool — bypass-mitigation
##     chip damage tunable per class.
##
## "Forced-deallocation lives elsewhere" in AllocationSystem comments —
## that elsewhere is here.
func _on_node_depleted(node: SkillNode) -> void:
	if node == null or allocation_system == null:
		return
	var defender: Entity = node.owned_by
	if defender == null:
		return
	# Cascade snapshot — must be computed BEFORE removing the depleted node
	# from the navigator mirror, or its islanded set goes stale.
	var cascade: Array[SkillNode] = [node]
	if defender.navigator != null and defender.core_location != null:
		cascade.append_array(defender.navigator.nodes_islanded_by_removing(
				node, defender.core_location))
	var board: StatBoard = defender.stat_board
	# Per-cascade dealloc damage — read once, applied per cascaded node. Older
	# hand-authored boards lacking the stat fall back to the def default (1).
	var hp_per_node: float = 1.0
	if board != null and board.dealloc_damage != null:
		hp_per_node = float(board.dealloc_damage.value)
	# BFS the cascade set from impact (in original graph topology) so VFX can
	# ripple outward layer-by-layer. Computed before force_deallocate to keep
	# the navigator state coherent — graph edges still exist either way, but
	# owner state is what changes mid-loop.
	var layers: Array = _cascade_layers(node, cascade)
	cascade_started.emit(layers, defender)
	# #491: the entity-death strip no longer needs a lethality PREDICTION here
	# — `AllocationSystem._on_entity_died` (fired synchronously by the
	# `health.deplete → depleted → die() → entity_died` chain from inside the
	# loop below, same as before #485) wraps its own strip in
	# `RevealRecorder.push_strip_scope()`, so its NODE_OWNER_LOST events
	# record with the correct staggered `t` — inherited from whatever cause
	# scope is open at the moment `health` actually crosses 0 — with no
	## attribution logic needed; see #488's "the system predicts its own
	# future" for what this replaces.
	var current_base := RevealRecorder.current_t()
	for i in range(layers.size()):
		RevealRecorder.push_cause(current_base + i * RevealTimeline.CASCADE_STEP)
		for n in layers[i]:
			if n == null or n.owned_by != defender:
				continue
			# Snapshot the fill BEFORE force_deallocate — owner_changed zeroes
			# allocation_level via _refresh_alloc_count, so any read after the
			# call returns 0 and the wound count / damage multiplier would silently
			# collapse (#337; same shape as LootSystem's pre-cleanup snapshot). A
			# 2/2 node costs 2 wounds and 2x dealloc_damage; the maxi(1, ·) floor
			# keeps the pre-staking 1/1 costs exactly as they were.
			var fill: int = n.allocation_level
			allocation_system.force_deallocate(n)
			if board != null:
				if board.skill_points != null:
					board.skill_points.wound(maxi(fill, 1))
				if board.health != null and hp_per_node > 0.0:
					var dmg: float = hp_per_node * float(maxi(fill, 1))
					# #491: recorded at the SAME `t` as this layer's
					# NODE_OWNER_LOST — the core bar chips down staggered, one
					# cascade layer at a time, same rhythm as the node paint.
					# A lethal deplete re-enters through die() from inside
					# this call (health.deplete → depleted → ... → die()),
					# which would otherwise record ENTITY_DEATH ahead of this
					# event — record BEFORE mutating, patch `to_value` after,
					# same pattern as SkillNode.take_damage's core-overflow
					# branch.
					var before_health: float = board.health.current
					var health_event := RevealRecorder.entity_health(defender, before_health, before_health)
					board.health.deplete(dmg)
					health_event.to_value = board.health.current
		RevealRecorder.pop_cause()


## BFS the cascade set from [param impact] over graph edges restricted to
## the cascade. Returns Array[Array[SkillNode]] where [i] holds every cascade
## node at distance i from impact ([0] == [impact]). Falls back to a single
## layer when [member graph] is unset (headless tests).
func _cascade_layers(impact: SkillNode, cascade: Array[SkillNode]) -> Array:
	if graph == null:
		var lone: Array[SkillNode] = []
		lone.append_array(cascade)
		return [lone]
	var in_cascade: Dictionary[SkillNode, bool] = {}
	for n in cascade:
		if n != null:
			in_cascade[n] = true
	var visited: Dictionary[SkillNode, bool] = {impact: true}
	var first_layer: Array[SkillNode] = [impact]
	var layers: Array = [first_layer]
	var frontier: Array[SkillNode] = [impact]
	while not frontier.is_empty():
		var next_frontier: Array[SkillNode] = []
		for n in frontier:
			for nb in graph.get_neighbours(n):
				if not in_cascade.has(nb) or visited.has(nb):
					continue
				visited[nb] = true
				next_frontier.append(nb)
		if not next_frontier.is_empty():
			layers.append(next_frontier)
		frontier = next_frontier
	# Defensive: any cascade node BFS missed (shouldnt happen by construction)
	# parks on an outermost layer so it still gets a VFX.
	var orphans: Array[SkillNode] = []
	for n in cascade:
		if n != null and not visited.has(n):
			orphans.append(n)
	if not orphans.is_empty():
		layers.append(orphans)
	return layers


