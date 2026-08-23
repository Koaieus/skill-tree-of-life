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
## The same moment, carrying the APPLIED outcome — for a presentation observer
## that needs to know what the attack will touch and when (#524:
## [CameraDirector] frames the from->to span). A sibling of
## [signal attack_launched] rather than a widening of it: that one has six
## production listeners and ~ten test call sites, none of which want the
## outcome.
##
## Both the authority path and the peer replay path funnel through
## [method _commit], so an observer here sees the applied outcome and never
## intent — `.claude/rules/multiplayer-sync.md` for free.
##
## [param attacker] is passed explicitly rather than read off the outcome,
## because an outcome with no hits carries no attacker.
signal attack_committed(outcome: AttackOutcome, attacker: Entity)
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
## The queue an attack is applied through (#511). Optional: without one,
## [method launch_attack] applies straight, which is what every headless
## fixture and the editor do. Wired by [CommandApplier] itself at `_ready`
## rather than by a second NodePath export, so "the applier that will call me
## back" and "the applier I submit to" cannot be two different objects.
var command_applier: CommandApplier = null

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


## Commit the active plan — the entry point every caller still uses (the HUD
## launch buttons, [AiController]). Since #511 this is a thin front for a
## [LaunchAttackCommand]: build it, submit it, and wait out the queue. The
## work itself lives in [method apply_launch_command], which the
## [CommandApplier] calls back — see [LaunchAttackCommand] for why one command
## type covers both "resolve and apply this" and "replay what the authority
## did".
##
## Awaits the whole action, not just the mutation, exactly as before.
func launch_attack() -> void:
	var command := build_launch_command()
	if command == null:
		return
	# Routed through the applier when one is wired, so an attack is an ordinary
	# confirmed command that [CommandLink] mirrors like every other verb. This
	# does NOT return early: `submit` drains synchronously up to the first
	# await inside the mutation loop, and parking on `applying_changed` after
	# it means every existing caller — the HUD launch buttons, `await
	# bs.launch_attack()` in [AiController] — still resumes when the WHOLE
	# swing is done, exactly as before.
	if command_applier != null:
		# Wait for THIS command, not for the queue to empty. `applying_changed`
		# would be the shorter spelling and is wrong twice: it fires when the
		# whole drain ends (so a command queued behind this one delays the
		# return), and a `launch_attack` raised from inside another command's
		# application would park on a signal that cannot fire until the drain
		# it is blocking completes — a hang. Every drained command emits
		# `command_applied`, so this loop always makes progress.
		var finished: Array[bool] = [false]
		var on_applied := func(applied: Command, _ok: bool) -> void:
			if applied == command:
				finished[0] = true
		command_applier.command_applied.connect(on_applied)
		command_applier.submit(command)
		while not finished[0] and command_applier.is_applying:
			await command_applier.command_applied
		command_applier.command_applied.disconnect(on_applied)
		return
	# No applier (headless fixtures, the editor, any level that has not mounted
	# one): apply straight. The seam is what #511 builds; a second code path
	# for offline is not, so this is the same method the applier would call.
	@warning_ignore("redundant_await")
	await apply_launch_command(command)


## The active plan as a [LaunchAttackCommand], or null if there is nothing
## launchable. Runs the checks that need the LIVE plan and are cheap to answer
## before anything is queued — is there a plan, is it valid, is somebody's turn
## — and stamps the per-attack seed.
##
## [b]The seed is stamped HERE, not at resolve.[/b] It is an input to the
## resolution, and putting it on the command makes the artifact
## self-describing: (plan + seed) is everything an authority needs to re-resolve
## and compare. `apply_launch_command` copies it onto the plan before calling
## [method AttackPlan.resolve], so "stamp before resolving" still holds.
func build_launch_command() -> LaunchAttackCommand:
	if not is_attacking or is_launching:
		push_warning("BattleSystem.launch_attack: no plan, or already launching")
		return null
	if not attack_plan.is_valid():
		push_warning("BattleSystem.launch_attack: invalid plan: %s" % str(attack_plan.validate()))
		return null
	var entity := turn_manager.current_entity if turn_manager != null else null
	if entity == null:
		push_warning("BattleSystem.launch_attack: no current entity")
		return null
	return LaunchAttackCommand.new(
			entity.entity_id, attack_plan.to_dict(graph), _seed_source.randi())


## Apply [param command] — the [CommandApplier]'s entry point, and the one
## place an attack mutates the world.
##
## [b]ONE launch path (#536).[/b] There used to be two — `_launch_as_authority`,
## which resolved and applied its own outcome against the real world, and
## `_replay_launch`, which reconstructed a record. The authority now does both:
##
## [codeblock]
## empty record -> COMPUTE: resolve on a shadow, capture the record, confirm
## every machine -> REPLAY:  rebuild that record, land it on the BeatClock
## [/codeblock]
##
## The confirm still fires from [method _commit], at the mutation-settle point,
## even though the payload is finished an await earlier — see the note there.
##
## Per #498: [i]"the host becomes a peer of itself; it is the only one that
## computes, not the only one that replays."[/i] The payload still decides which
## half runs, never a peer role (see [LaunchAttackCommand]) — an empty record
## just means "nobody has computed this yet", and only the authority ever
## receives one.
##
## [b]The round trip through capture -> rebuild is the point, not waste.[/b]
## Reusing the computed [AttackOutcome] object for the live pass would land the
## same hits a second time, and every land-time write on them is one-shot:
## [method CritRoll.apply] multiplies `amount` in place, `hp_before`/`hp_after`
## would be overwritten with post-cascade numbers, and — worst — a
## [member HitInstance.deallocations] left over from the shadow would make
## [method _on_node_depleted] take its RECORDED branch and re-apply a stale
## cascade set. Rebuilding mints fresh hits, so none of that is possible by
## construction rather than by discipline. Do not "optimise" it away.
func apply_launch_command(command: LaunchAttackCommand) -> bool:
	if command == null or is_launching:
		return false
	var plan: AttackPlan
	# "Did THIS machine compute the record", which is the only thing that
	# decides who confirms — never a peer role (see [LaunchAttackCommand]).
	var computed := command.record.is_empty()
	if computed:
		plan = attack_plan
		if plan == null:
			# An initiate for a plan this peer does not hold. Rebuilding one
			# here would be the intent-up path, which is #463 — refuse loudly
			# instead of guessing what the sender had armed.
			push_warning("BattleSystem: launch_attack initiate with no live plan")
			return false
		# Re-validated HERE, not only in `build_launch_command`: a command can
		# sit in the queue while the world moves under it (a cascade frees the
		# pivot, the target is captured). An invalidated plan resolves to an
		# EMPTY outcome whose `ap_cost` still defaults to 1, so skipping this
		# spends AP on nothing.
		if not plan.is_valid():
			push_warning("BattleSystem: plan went invalid before apply: %s" % str(plan.validate()))
			return false
		if not _compute_record(plan, command):
			return false
	else:
		plan = AttackPlanCodec.from_dict(command.plan, graph)
		if plan == null:
			return false
		attack_plan = plan
		# Melee draws off `last_trajectory` / `last_events`, which only
		# [method MeleeAttackPlan.resolve_against] fills in. Its returned
		# outcome is DISCARDED — the record is what lands, and `resolve()` runs
		# against a throwaway shadow, so re-simulating to DRAW mutates nothing
		# (see [AttackRecord]). Skipped when there is no preview mounted, so a
		# headless peer pays nothing for an animation it won't play.
		if plan is MeleeAttackPlan and melee_preview != null:
			plan.resolve()
	# Everyone, authority included, from here down. The command rides along only
	# so the authority can confirm at its settle point — see [method _commit].
	var outcome := AttackRecord.rebuild(command.record, graph)
	@warning_ignore("redundant_await")
	await _commit(plan, outcome, command if computed else null)
	return true


## The COMPUTE half — authority only, and the one place in the codebase that
## decides what an attack does. Stamps [param command]'s record and returns
## true, or refuses on affordability and returns false.
##
## [b]Nothing real is touched here.[/b] The whole pass runs against a
## [method CombatWorld.shadow]: the hits land, the cascades cascade, mitigation
## is read node-locally and every mode's land-time gate fires — all on detached
## slices. What comes out is the post-apply [AttackRecord], which
## [method apply_launch_command] then replays on the live world exactly as a
## peer does. Owner call 2026-08-23, [i]"shadow always"[/i]: it leaves
## [OutcomeApplier] the sole mutator of the real world, so there is no
## "already applied" state anywhere to detect and suppress.
##
## The affordability gate is the last thing that can still refuse an attack, and
## it reads the REAL board — the costs are real even though the resolution is
## not.
func _compute_record(plan: AttackPlan, command: LaunchAttackCommand) -> bool:
	# Stamp BEFORE resolving: the seed is an input to this resolution, and
	# `outcome.resolve_seed` carries it back out so the artifact can
	# reproduce itself. Every preview and AI rollout up to this point ran on
	# the unstamped (0) stream, so the committed roll is genuinely fresh.
	plan.resolve_seed = command.resolve_seed
	var world := CombatWorld.shadow()
	# Freed on EVERY exit below, including the refusals — a shadow holds
	# reference cycles ([method EntityCombat.free_shadow]) and leaks without it.
	var outcome := plan.resolve_against(world)
	var affordable := _can_afford(plan, outcome)
	if affordable:
		command.record = AttackRecord.capture(outcome, graph)
	world.free_shadow()
	return affordable


## Can [param plan]'s attacker pay for [param outcome]? Reads the LIVE pools —
## an attack computed on a shadow is still paid for out of the real board.
func _can_afford(plan: AttackPlan, outcome: AttackOutcome) -> bool:
	var entity := plan.attacker
	var board: StatBoard = entity.stat_board if entity != null else null
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null and ap_pool.available() < outcome.ap_cost:
		push_warning("BattleSystem.launch_attack: insufficient AP (%d < %d)" \
				% [int(ap_pool.current), outcome.ap_cost])
		return false
	var mana_pool: PoolStat = board.mana if board != null else null
	if outcome.mana_cost > 0 and mana_pool != null \
			and mana_pool.available() < outcome.mana_cost:
		push_warning("BattleSystem.launch_attack: insufficient mana (%d < %d)" \
				% [int(mana_pool.current), outcome.mana_cost])
		return false
	return true


## The APPLY half — what every machine runs, authority included, on the outcome
## rebuilt from the record. There is no longer a second version of this for the
## machine that computed it.
##
## Costs are deducted up front; the plan itself stays live through the whole
## await (#406 — a melee plan's attached temp-upgrade addons must keep
## rendering through the live swing) and is cleared in one place, after.
## `is_launching` — not `attack_plan != null` — is what blocks a second
## launch during the await window.
##
## [b]Phases overlap, and that is the point.[/b] The arrow is in the air while
## the mutation loop waits out its `arrival_time`, so the health bar, the
## shatter, the fog and the damage number all move on the same beat — they are
## all reading the model, and the model changes when the arrow lands. The rule
## this does not break is [b]never frame-ordered mutation[/b] — see [BeatClock].
## VFX still gates nothing: dropping every frame of the animation leaves the
## applied world identical, because the loop waits on its own timer and not on
## `attack_vfx.play`.
func _commit(plan: AttackPlan, outcome: AttackOutcome,
		command: LaunchAttackCommand) -> void:
	is_launching = true
	var entity := plan.attacker
	var board: StatBoard = entity.stat_board if entity != null else null
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null:
		ap_pool.deplete(float(outcome.ap_cost))
	var mana_pool: PoolStat = board.mana if board != null else null
	if outcome.mana_cost > 0 and mana_pool != null:
		mana_pool.deplete(float(outcome.mana_cost))
	var launched_spell: SpellDef = (plan as MagicAttackPlan).spell if plan is MagicAttackPlan else null
	attack_launched.emit(plan.mode, launched_spell)
	# Un-awaited, like every other observer on this path: `_apply_outcome`
	# below is what waits on the beat clock, and anything awaited here would
	# gate the mutation loop.
	attack_committed.emit(outcome, entity)
	# Costs are already deducted; the plan is still live, so an effect can read
	# its targets. Replaces the issue's `_on_battle_start` — there is no battle.
	if plan.attacker != null:
		plan.attacker.dispatch(&"_on_attack_launched", [plan.mode, launched_spell])
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
	var melee_plan: MeleeAttackPlan = plan as MeleeAttackPlan
	if melee_plan != null and melee_preview != null:
		# Melee: the MeleePreview (which has the ghost mounted) animates the
		# swing on the same `BladeHitEvent.t` clock the applier lands hits on,
		# so the blade now visibly reaches a node as that node takes its hit.
		_run_melee_preview(melee_plan)
	elif attack_vfx != null:
		var coord_scene: PackedScene = null
		var magic_plan: MagicAttackPlan = plan as MagicAttackPlan
		if magic_plan != null and magic_plan.spell != null:
			coord_scene = magic_plan.spell.vfx_coordinator_scene
		_run_attack_vfx(outcome, coord_scene)
	# World mutation, on the beat clock. Awaited: `is_launching` gates on the
	# WORLD being finished, never on the animation.
	await _apply_outcome(outcome)
	# Nothing is CAPTURED here anymore (#536) — the record was complete before
	# this method was entered; it is the record this pass just replayed. The
	# confirm did not move with it, and that is deliberate:
	#
	# [b]Confirmation means "applied here", not "computed here".[/b]
	# [CommandLink] stamps `WorldFingerprint.compute(graph)` onto the payload it
	# broadcasts from [signal CommandApplier.command_confirmed], and the
	# receiving peer compares that against its own world AFTER applying. Confirm
	# before the mutation and every attack would broadcast a pre-command
	# fingerprint and report a divergence that isn't there — with nothing in the
	# unit suite positioned to notice, since the check lives on the wire.
	#
	# Still ahead of the animation tail, which is the reason
	# [signal CommandApplier.command_confirmed] exists at all: `command_applied`
	# cannot fire until this coroutine returns, so mirroring off that used to
	# make a peer sit out the host's whole swing before starting its own.
	if command != null and command_applier != null:
		command_applier.confirm(command)
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
	await OutcomeApplier.apply(outcome, CombatWorld.live(), _beat_clock)
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
## [b]This is the live cascade's ENTRY, no longer its implementation[/b]
## (#518). The set, the pre-strip `allocation_level` read, the wound, the chip
## and the [DeallocEntry] record all live in [method EntityCombat.apply_cascade]
## — one driver, which a SHADOW reaches directly (its `notify_depleted` is
## never called, so this handler never runs for one). What stays here is what
## the slice cannot do: the VFX layer BFS, which needs [member graph], and the
## `cascade_started` announcement.
##
## [b]Order is load-bearing.[/b] The set is queried, BFS'd into layers and
## announced BEFORE anything is stripped — [AllocationVFX] staggers its shatter
## spawn off those layers, and a strip that ran first would hand the
## coordinator a world that had already changed. That is also why
## [method EntityCombat.cascade_set] is a separate, pure query rather than
## something [method EntityCombat.apply_cascade] does for itself.
##
## "Forced-deallocation lives elsewhere" in AllocationSystem comments —
## that elsewhere is [EntityCombat]; this forwards to it.
func _on_node_depleted(node: SkillNode, source: Variant = null) -> void:
	if node == null or allocation_system == null:
		return
	var defender: Entity = node.owned_by
	if defender == null:
		return
	var combat := defender.get_combat()
	# ── Recorded, or derived? ────────────────────────────────────────────────
	# ANY machine replaying an [AttackRecord] arrives here with the cascade the
	# authority ran already on its hit (#518). It applies THAT set rather than
	# walking its own navigator for one: under the filtered-delta model
	# (docs/domain/multiplayer-sync-model.md) a fogged client may not hold the
	# nodes that walk would visit, so the derivation is not merely redundant,
	# it is wrong.
	#
	# [b]The invariant this rests on:[/b] a non-empty `deallocations` means
	# "this hit has already been cascaded", NOT "I am a peer" — and since #536
	# the two no longer coincide even loosely, because the authority replays a
	# record too. Its DERIVING pass happens on a shadow world, inside
	# [method _compute_record], where `host == null` sends
	# [method NodeCombat.take_damage] down its own `cascade_from` branch and
	# never reaches this handler at all.
	#
	# So the derive branch below is now for depletions that are not an attack
	# replay: anything else that damages a node to zero on the live world. It
	# stays because those exist, not as the authority's path.
	#
	# This is also where #501's warning landed. A hit must be applied exactly
	# ONCE per world, or the second pass takes the replay branch and re-applies
	# a stale set; magic now lands its waves during resolution, so the thing
	# that keeps this true is that the authority never re-uses a computed
	# outcome — it captures and rebuilds. See
	# [method apply_launch_command].
	var recorded: Array[DeallocEntry] = []
	if source is HitInstance:
		recorded = (source as HitInstance).deallocations
	var cascade: Array[NodeCombat] = []
	if recorded.is_empty():
		# Queried BEFORE the strip — removing the depleted node from the
		# navigator mirror first would make its own islanded set go stale.
		cascade = combat.cascade_set(node.get_combat())
	else:
		for e in recorded:
			if e.node != null:
				cascade.append(e.node.get_combat())
	var cascade_nodes: Array[SkillNode] = []
	for n in cascade:
		var real := combat.real_node_for(n)
		if real != null:
			cascade_nodes.append(real)
	# BFS the cascade set from impact (in original graph topology) so VFX can
	# ripple outward layer-by-layer.
	var layers: Array = _cascade_layers(node, cascade_nodes)
	cascade_started.emit(layers, defender)
	# #504: the cascade mutates SYNCHRONOUSLY, every layer inside this one beat,
	# and it must stay that way. This runs from `Events.skill_node_depleted`
	# inside `take_damage` inside a landing — and an awaiting signal handler
	# does NOT block its emitter, so staggering the MUTATION here would unwind
	# behind the applier's next beat, breaking both the driver's own
	# `owner() != self` re-entrancy guard and the synchronous-cleanup contract
	# in `.claude/rules/entity-death.md`. The visible layer-by-layer ripple is
	# presentation: `cascade_started` carries `layers` in BFS order and
	# [AllocationVFX] staggers the shatter spawn off it.
	#
	#
	# Applied in LAYER order, which is the order this handler has always used.
	# It is the same SET either way, but not the same sequence, and the
	# sequence is observable: the chip can cross the defender's `health` 0
	# partway through, and which nodes were already stripped when
	# `Events.entity_died` fires decides what `deallocate_all_owned` finds
	# left. Feeding the driver the flattened layers keeps that identical
	# rather than "identical set, near enough".
	var ordered: Array[NodeCombat] = []
	for layer in layers:
		for n: SkillNode in layer:
			if n != null:
				ordered.append(n.get_combat())
	var entries := combat.apply_cascade(ordered, allocation_system)
	# Record the cascade back onto the hit that caused it (#518). This handler
	# runs synchronously inside `NodeCombat.take_damage`, so the hit is still
	# mid-application and the entries land on it before it is read by anything
	# — the AI's scoring, or [AttackRecord]'s capture on the way to the wire.
	#
	# Never on a REPLAY: the recorded entries are the authority's, and
	# overwriting them with a peer's own would turn a replay back into a
	# derivation on the next capture.
	#
	# What a peer replays is the SET; the wound and chip it charges are
	# recomputed from the same inputs (the pre-strip fill it holds, its own
	# `dealloc_damage`) rather than read off the record. That is deliberate and
	# is not the derivation this issue removes — those inputs are already
	# synchronised by the command stream, while the islanded SET depends on
	# topology a fogged client may not hold at all. The recorded numbers ride
	# along for AI scoring and for a client that wants to draw the toast.
	if recorded.is_empty() and source is HitInstance:
		(source as HitInstance).deallocations = entries


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
