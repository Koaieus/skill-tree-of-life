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

## Design B (#504): the clock the CURRENT attack's mutation loop is walking, or
## null between attacks. Held so [method drain_pending_mutations] can cut the
## window short — the one mitigation for B's single real risk, a loop
## interrupted mid-volley leaving its remaining hits permanently unlanded.
var _beat_clock: BeatClock = null

## True while an attack's VFX coroutine is parked. See `launch_attack` for why
## the flag exists rather than a bare `await _vfx_finished`.
##
## [b]Load-bearing invariant: nothing may free the animating node mid-play.[/b]
## A coroutine awaiting a freed object is silently dropped, so `_vfx_finished`
## would never fire, `_reset()` would never run, and the plan would stay armed
## forever — a permanent hang, not a cosmetic glitch. This is not theoretical:
## it happened to melee while building #504 (the cascade now fires mid-swing,
## and `MeleePreview._refresh` tore down the blade `launch()` was awaiting),
## and `MeleePreview._live_swing` is the guard that closes it.
##
## Audited for the ranged/magic path as of #504: the ONLY free of a coordinator
## is `AttackVFX.play`'s own `coord.queue_free()`, after its await returns, and
## nothing frees the `%AttackVFX` mount outside level teardown (where
## [method drain_pending_mutations] covers the mutation half). If a path is
## added that can free a coordinator mid-`play`, this parks forever — give it
## the same treatment `_live_swing` got.
var _vfx_running: bool = false
signal _vfx_finished

## Land the whole outcome synchronously instead of on the beat clock (#504).
## For fixtures and headless callers that read world state on the line after
## `launch_attack`. Production leaves this false: the beat clock IS the
## presentation clock, so turning it off makes an attack land invisibly.
##
## Not inferred from whether `attack_vfx` / `melee_preview` are mounted —
## see [method _apply_outcome].
var instant_mutation: bool = false


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

## Toggle a temp upgrade (#406) onto [param node] of the live [MeleeAttackPlan],
## refunding an identical one already there. Moved here from
## `PlayerInputController.apply_armed_temp_upgrade_to` by #510 — **owner call
## 2026-08-21:** *"BattleSystem or AttackPlan. (or a AddonManager system would be
## cleaner … but i'm afraid that adds a lot of complexity while i want to SOLVE
## issues and get stuff done, not create more)."* BattleSystem, because it is
## what mounts addons on the live plan; an `AddonManager` is out of scope.
##
## Takes [param upgrade] EXPLICITLY rather than reading a controller's armed
## state: the arm is local plan-building that never crosses a wire, so it stays
## in [PlayerInputController], and [ToggleTempUpgradeCommand] carries the
## catalog id instead (#509). Pass a
## [constant MeleeAttackPlan.TEMP_UPGRADE_CATALOG] entry — resolve one with
## [method MeleeAttackPlan.upgrade_by_id].
##
## Returns whether the toggle landed. A refusal is announced on
## [signal Events.node_action_denied] here, where the reason is knowable —
## whether the CLICK was consumed is a routing question the caller answers on
## its own.
func toggle_temp_upgrade_on(node: SkillNode, upgrade: Variant) -> bool:
	var plan := attack_plan as MeleeAttackPlan
	if plan == null or node == null or upgrade == null:
		return false
	if upgrade is Dictionary and (upgrade as Dictionary).is_empty():
		return false
	if plan.toggle_temp_upgrade(node, upgrade):
		return true
	var reason := "temp_upgrade_denied_slot_full" \
			if not node.can_attach_addon(upgrade.script) \
			else "temp_upgrade_denied_budget"
	Events.node_action_denied.emit(node, reason)
	return false


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

## Mints the per-attack [member AttackPlan.resolve_seed] stamped by
## [method launch_attack]. The AUTHORITY owns this — under
## `docs/domain/multiplayer-sync-model.md` the host stamps every attack's
## seed and posts it with the outcome, so a peer can replay the attack
## exactly rather than re-rolling its own crits.
##
## Randomised at `_ready` for now, which makes each RUN's attacks unique
## while every attack WITHIN a run is individually reproducible from its
## stamp. #457 is where this stops being self-seeded and starts deriving
## from [member RunConfig.seed] — a one-line change here, deliberately not
## made now so the plumbing lands without waiting on the seed policy.
var _seed_source := RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_node_depleted.connect(_on_node_depleted)
	_seed_source.randomize()


## Commit the active plan. Three phases:
##   1. resolve() → AttackOutcome (the candidate set + attacker-side arithmetic;
##      see docs/domain/attack-timeline.md for what is frozen here and what is
##      re-read at land time)
##   2. apply the outcome ON THE BEAT CLOCK — each hit's world mutation happens
##      at its own `arrival_time`, in that order, with the forced-dealloc
##      cascade running synchronously inside each beat (#504, design B)
##   3. VFX runs CONCURRENTLY as a PURE OBSERVER — it reads
##      `outcome`/`melee_plan.last_events` to time its playback and never
##      mutates; then AP/plan cleanup
##
## [b]Phases 2 and 3 overlap, and that is the point.[/b] The arrow is in the
## air while the mutation loop waits out its `arrival_time`, so the health bar,
## the shatter, the fog and the damage number all move on the same beat — they
## are all reading the model, and the model changes when the arrow lands.
##
## The rule this does not break is [b]never frame-ordered mutation[/b] — see
## [BeatClock]. VFX still gates nothing: dropping every frame of the animation
## leaves the applied world identical, because the loop waits on its own timer
## and not on `attack_vfx.play`.
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
	# Stamp BEFORE resolving: the seed is an input to this resolution, and
	# `outcome.resolve_seed` carries it back out so the artifact can
	# reproduce itself. Every preview and AI rollout up to this point ran on
	# the unstamped (0) stream, so the committed roll is genuinely fresh.
	attack_plan.resolve_seed = _seed_source.randi()
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
	# VFX starts FIRST and UN-AWAITED, so it runs alongside the mutation loop
	# below: the arrow is in the air while the loop waits out its
	# `arrival_time`. It is still a pure observer — it reads the outcome to
	# time itself and never mutates, and the loop waits on its own timer rather
	# than on any animation, so a dropped frame cannot change gameplay.
	#
	# The un-awaited call runs synchronously up to the coroutine's first await,
	# which is what makes `_vfx_running` trustworthy on the line after it:
	# true means "parked, will emit later", false means "already finished".
	# Checking it before parking on `_vfx_finished` is what keeps a
	# fully-synchronous VFX path (a stub, a mode with nothing to draw) from
	# emitting into no listener and hanging the launch forever.
	_vfx_running = false
	var melee_plan: MeleeAttackPlan = attack_plan as MeleeAttackPlan
	if melee_plan != null and melee_preview != null:
		# Melee: the MeleePreview (which has the ghost mounted) animates the
		# swing on the same `BladeHitEvent.t` clock the applier lands hits on,
		# so the blade now visibly reaches a node as that node takes its hit.
		_run_melee_preview(melee_plan)
	elif attack_vfx != null:
		var coord_scene: PackedScene = null
		var magic_plan: MagicAttackPlan = attack_plan as MagicAttackPlan
		if magic_plan != null and magic_plan.spell != null:
			coord_scene = magic_plan.spell.vfx_coordinator_scene
		_run_attack_vfx(outcome, coord_scene)
	# World mutation, on the beat clock. Awaited: `is_launching` gates on the
	# WORLD being finished, never on the animation.
	await _apply_outcome(outcome)
	# Then wait out the animation too, before releasing anything. `is_launching`
	# spans the WHOLE action, not just the mutation: it is what blocks a second
	# launch, and the plan stays live behind it because a melee plan's
	# temp-upgrade addons (#406) must keep rendering through the swing. Clearing
	# it at mutation-end would let a player arm and fire again mid-swing with
	# the previous plan still mounted. VFX ordinarily outlasts the mutation
	# window anyway — an arrow lingers after it lands.
	if _vfx_running:
		await _vfx_finished
	# is_launching flips false BEFORE _reset() (not after) — _reset()'s
	# attack_plan = null synchronously fires attack_plan_changed, and
	# PlayerInputController's gate-refresh listener reads is_launching the
	# instant that signal fires. Clearing it after would have that listener
	# observe a stale "still launching" and never re-enable AttackModeBar.
	# Keep these two adjacent: callers settle on `is_launching` and expect the
	# plan to be cleared by the time it goes false.
	is_launching = false
	_reset()


## Runs [MeleePreview] to completion, then reports. See `launch_attack` for why
## this is a named coroutine rather than an inline un-awaited call: GDScript
## cannot hold a handle to a `-> void` coroutine, so the completion report has
## to be a signal the caller can park on.
func _run_melee_preview(melee_plan: MeleeAttackPlan) -> void:
	_vfx_running = true
	await melee_preview.launch(melee_plan)
	_vfx_running = false
	_vfx_finished.emit()


## Runs the ranged/magic coordinator to completion, then reports — see
## [method _run_melee_preview].
func _run_attack_vfx(outcome: AttackOutcome, coord_scene: PackedScene) -> void:
	_vfx_running = true
	if coord_scene != null:
		await attack_vfx.play(coord_scene, outcome)
	else:
		await attack_vfx.play_ranged_volley(outcome)
	_vfx_running = false
	_vfx_finished.emit()


## The one place world mutation happens for an attack: every hit in
## [member AttackOutcome.hits] lands via [OutcomeApplier] — which, via
## take_damage → Events.skill_node_depleted → _on_node_depleted (both
## synchronous), also runs the forced-dealloc cascade. VFX never calls this;
## it only replays what already landed. See the class-level VFX note.
##
## Presentation clock (#504): the applier walks the hits on a [BeatClock],
## landing each at its own `arrival_time`. What is drawn is the model, at every
## beat — there is no view store and no replay.
##
## [member instant_mutation] is the opt-out, and it is deliberately NOT
## inferred from whether VFX happens to be mounted. #474's acceptance is that
## the applied world is identical whether or not `attack_vfx` is wired — so
## making the clock depend on that is exactly the thing that must not matter.
## A fixture that wants the whole outcome on one line says so out loud.
func _apply_outcome(outcome: AttackOutcome) -> void:
	_beat_clock = BeatClock.instant_clock() if instant_mutation \
			else BeatClock.for_tree(get_tree())
	@warning_ignore("redundant_await")
	await OutcomeApplier.apply(outcome, _beat_clock)
	_beat_clock = null


## Land every hit the current attack has not landed yet, immediately. Called on
## scene teardown ([method GameRoot._exit_tree]): design B's one real risk is a
## mutation loop interrupted mid-window, which would leave the world valid but
## permanently wrong. No-op when no attack is in flight.
func drain_pending_mutations() -> void:
	if _beat_clock != null:
		_beat_clock.drain()


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
	# #504: the cascade mutates SYNCHRONOUSLY, every layer inside this one beat,
	# and it must stay that way. This runs from `Events.skill_node_depleted`
	# inside `take_damage` inside a landing — and an awaiting signal handler
	# does NOT block its emitter, so staggering the MUTATION here would unwind
	# behind the applier's next beat, breaking both the
	# `owned_by != defender` guard below and the synchronous-cleanup contract
	# in `.claude/rules/entity-death.md`. The visible layer-by-layer ripple is
	# presentation: `cascade_started` carries `layers` in BFS order and
	# [AllocationVFX] staggers the shatter spawn off it.
	for i in range(layers.size()):
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
					# #504: the core bar draws `board.health` directly and
					# hears its `current_changed`, so the chip is announced by
					# the mutation itself — nothing to record or patch here.
					board.health.deplete(dmg)


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
