@tool
class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

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

## The replay is STARTING — the whole wind-up (and any `record_ready` hold)
## is spent and the mutation clock is about to start. Fires once per launch,
## for every mode (ADR 0027): right before [method MeleePreview.launch] for
## melee, right before the coordinator runs for ranged/magic — in both cases
## with the outcome's schedule already compiled so an observer can size itself
## off [method OutcomeSchedule.duration]. [CameraDirector] re-sizes its hold on
## this beat (#894) rather than on a wall-clock re-derivation of the wind-up,
## which could not see the hold and drifted from the swing.
signal attack_replay_started(outcome: AttackOutcome)
## Forced-deallocation cascade about to run. `layers[i]` holds every cascade
## node at BFS graph-distance `i` from the impact node; `layers[0] == [impact]`.
## Emitted BEFORE the synchronous force_deallocate loop so VFX can snapshot
## owner colour + schedule a staggered ripple. See docs/domain/allocation-vfx.md.
##
## Two independent emitters (#837 added the second): [method _on_node_depleted]
## for a non-core node reaching 0 HP (impact = that node), and
## [method _on_entity_dying] for the entity itself dying (impact = its core) —
## the whole-board strip [AllocationSystem.deallocate_all_owned] runs
## un-staggered. Both fire BEFORE their respective strip; neither sequences the
## other (#257 scenario 2 just chains: the node-cascade's own wave completes,
## then a chip death fires this one separately).
signal cascade_started(layers: Array, defender: Entity)

## The in-flight launch's [AttackRecord] just became available. Private
## plumbing for [method await_record_ready] — park on that, never on this.
signal record_ready

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
@export var graph: Graph
## What draws a launch — the wind-up, the swing or volley, the camera's focus
## (#1196). Null, or the no-op [AttackStage] base, is a headless peer: nothing
## staged, nothing held, and a world identical to a presented launch's (#474).
## The level mounts an `AttackPresenter`; this system names no `ui/` class.
@export var stage: AttackStage
## The queue an attack is applied through (#511). Optional: without one,
## [method launch_attack] applies straight, which is what every headless
## fixture and the editor do. Wired by [CommandApplier] itself at `_ready`
## rather than by a second NodePath export, so "the applier that will call me
## back" and "the applier I submit to" cannot be two different objects.
## Who THIS machine plays, pushed in by [GameRoot] alongside the copies
## [CameraDirector] and [CommandApplier] already get. Read only through
## [method OutcomeSchedule.actor_rate], so the seat question has one asker here
## rather than a second copy of the rule. Null outside a wired level, which
## [method OutcomeSchedule.actor_rate] treats as unseated.
var seat_policy: SeatPolicy = null

## A debug multiplier on every presentation rate this system compiles, for the
## melee sandbox's playback slider (#820). [b]Sandbox-only[/b]: it never writes
## [member GameSettings.combat_time_scale] and never persists. Deliberately a
## plain instance var and not an `@export` — a tuning knob has no business in
## every level's inspector, and an instance var cannot leak across test files
## the way a process-global would (#815).
var presentation_rate_scale: float = 1.0

## See [method await_record_ready]. False means the record is already in hand,
## which is every path that exists today.
var _record_pending: bool = false

## Latched by [method drain_pending_mutations] for the rest of the current
## launch. The wind-up (#559) put a SECOND clock on this path, so a drain that
## released the first one would otherwise be followed by `_apply_outcome`
## minting a fresh real-time clock against a tree that is going away — the
## drain has to outlive the clock it drained. Cleared on entry to
## [method _commit]. See [method _new_beat_clock].
var _draining: bool = false

var command_applier: CommandApplier = null

## Design B (#504): the clock the CURRENT attack's mutation loop is walking, or
## null between attacks. Held so [method drain_pending_mutations] can cut the
## window short — the one mitigation for B's single real risk, a loop
## interrupted mid-volley leaving its remaining hits permanently unlanded.
var _beat_clock: BeatClock = null

## Land the whole outcome synchronously instead of on the beat clock (#504).
## For fixtures and headless callers that read world state on the line after
## `launch_attack`. Production leaves this false: the beat clock IS the
## presentation clock, so turning it off makes an attack land invisibly.
##
## Not inferred from whether a [member stage] is mounted —
## see [method _apply_outcome].
var instant_mutation: bool = false

## How long after the LAST landing a coordinator-mode attack (ranged/magic)
## keeps [member is_launching] held — the "and breathe" beat between the world
## settling and the player being able to fire again.
##
## Release used to wait out the whole animation drain, which for a ranged
## volley meant the arrow's stick-and-fade: `LightArrow.hold_seconds` 0.35 +
## `fade_seconds` 0.4, three quarters of a second in which nothing about the
## world could still change. The arrows still linger — they are children of
## `%AttackVFX`, not of the plan, so they finish fading on their own long
## after `_reset()` — the player just no longer waits on them.
##
## Rides the same [BeatClock] as the mutation loop, so it is instant under
## [member instant_mutation] and [method drain_pending_mutations] cuts it
## short on teardown like any other beat.
##
## Melee is deliberately excluded: its plan (and the temp-upgrade addons
## mounted on it, #406) must stay live through the visible swing, so it still
## releases when the [member stage] stops holding it.
@export var release_beat: float = 0.12


## True while resolve()..VFX-await..AP-deduction is in flight, independent
## of whether the plan is still live (#406 — the plan now stays live
## through the melee await so its temp-upgrade addons render correctly).
## The one thing that blocks a second launch_attack() mid-swing.
var is_launching := false


## The offerable temp-upgrade kinds (#406, #1008) — authored data, wired to
## `attack/melee/temp_upgrade_catalog.tres` by the composing scene. The launch
## decode reads it to rebuild a plan's addons off the wire; the tray reads the
## offer. Optional: unwired, [method temp_upgrade_by_kind] answers null and
## [method temp_upgrade_kinds] is empty.
@export var temp_upgrade_catalog: TempUpgradeCatalog


## The catalog scene whose kind (scene path) is [param kind] — the door for a
## temp upgrade's wire identity — or null if unknown or no catalog is wired.
func temp_upgrade_by_kind(kind: String) -> PackedScene:
	if temp_upgrade_catalog == null:
		return null
	return temp_upgrade_catalog.by_kind(kind)


## The offerable ([member SkillNodeAddon.temp_placeable]) kinds in tray order; empty when no catalog is wired.
func temp_upgrade_kinds() -> Array[PackedScene]:
	if temp_upgrade_catalog == null:
		return []
	return temp_upgrade_catalog.offered()


## The launch-side teardown, at [method _commit]'s release: drops
## the [member stage]'s mount, announces [signal in_flight_plan_changed] with null,
## and resets the plan that was in flight (freeing its temp-upgrade addons). The
## attack level that armed it hears the release and mints a fresh one.
func _reset() -> void:
	if stage != null:
		stage.unmount()
	var plan := _in_flight_plan
	_in_flight_plan = null
	if plan == null:
		return
	in_flight_plan_changed.emit(null)
	plan.reset()


## The plan being launched right now, from [method _commit]'s entry to its
## release; null between launches. Read-only outside: the launch path is its
## one writer. Every reader of "the plan on screen during a swing" —
## [method presenter], [MeleePreview]'s replay pump, [CameraDirector] — reads
## this, never the seat's armed plan ([method ArmedStack.attack_plan]), because
## an AI's or a mirror's launch never passes through the seat.
var in_flight_plan: AttackPlan:
	get: return _in_flight_plan
var _in_flight_plan: AttackPlan = null

## [member in_flight_plan] was set ([method _commit] entry) or cleared (release,
## with null — after [member is_launching] drops, before the plan is reset). A
## reader of "the plan on screen" resolves `in_flight_plan ?? armed plan` and
## listens to this beside [signal ArmedStack.attack_plan_changed].
signal in_flight_plan_changed(plan: AttackPlan)


## Mint a fresh plan for [param mode], attacked by [param attacker], with no
## viewer fog. Null for [constant AttackMode.NONE]. Carries none of a seat's
## sticky tray preferences ([member ArmedStack.next_melee_cw],
## [member ArmedStack.selected_spell]) — an [AttackArmMode] layers those on its
## own plans; an explicit attacker gets the plan's own defaults.
func new_plan(mode: AttackMode, attacker: Entity) -> AttackPlan:
	return mint_plan(mode, attacker, null)


## The one plan minter, shared by [method new_plan] and the seat's attack
## levels ([AttackArmMode], which pass the seat's fog as [param vision]).
static func mint_plan(mode: AttackMode, attacker: Entity, vision: VisionSystem) -> AttackPlan:
	var p: AttackPlan
	match mode:
		AttackMode.MELEE: p = MeleeAttackPlan.new()
		AttackMode.RANGED: p = RangedAttackPlan.new()
		AttackMode.MAGIC: p = MagicAttackPlan.new()
		_: return null
	p.attacker = attacker
	if p is MagicAttackPlan:
		(p as MagicAttackPlan).viewer_vision = vision
	return p

## Mints the per-attack [member AttackPlan.resolve_seed] stamped by
## [method launch_attack]. The AUTHORITY owns this — under
## `docs/domain/multiplayer-sync-model.md` the host stamps every attack's
## seed and posts it with the outcome, so a peer can replay the attack
## exactly rather than re-rolling its own crits.
##
## Randomised at `_ready`, and it stays that way. Each RUN's attacks are
## unique while every attack WITHIN a run is individually reproducible from
## its stamp. #457 settled this the opposite way to what an earlier note here
## predicted — owner call, 2026-08-21: the run seed is procgen's and nothing
## else's, so the acceptance reads *"the resolved seed reaches `GraphProcgen`
## and nothing else. Do not thread it into `BattleSystem`, `SpellResolver`,
## `LootSystem`, or `SkillDustAddon`."* Reproducibility comes from the
## per-attack stamp, which is strictly better for sync: a run-level stream
## would couple every peer's result to having consumed prior draws in the same
## order — the ordering fragility that sank lockstep in #473.
##
## The consequence is deliberate: same seed, same MAP, not the same FIGHTS.
## See `.claude/rules/game-session.md`.
var _seed_source := RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_node_depleted.connect(_on_node_depleted)
	Events.entity_dying.connect(_on_entity_dying)
	_seed_source.randomize()



## Commit [param plan] — the HUD passes the seat's armed plan, an
## [AIController] the one it built with [method new_plan]. Since #511
## this is a thin front for a
## [LaunchAttackCommand]: build it, submit it, and wait out the queue. The
## work itself lives in [method apply_launch_command], which the
## [CommandApplier] calls back — see [LaunchAttackCommand] for why one command
## type covers both "resolve and apply this" and "replay what the authority
## did".
##
## Awaits the whole action, not just the mutation, exactly as before.
func launch_attack(plan: AttackPlan) -> void:
	var command := build_launch_command(plan)
	if command == null:
		return
	# Routed through the applier when one is wired, so an attack is an ordinary
	# confirmed command that [CommandChannel] mirrors like every other verb. This
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
	# one): run the applier's own two halves in the applier's own order. Not a
	# second code path for offline — these are the same two methods
	# [method CommandApplier._validate] and [method CommandApplier._apply] call,
	# and `prepare` is not optional (see [method apply_launch_command]).
	if not prepare_launch_command(command):
		return
	@warning_ignore("redundant_await")
	await apply_launch_command(command)


## [param plan] as a [LaunchAttackCommand], or
## null if there is nothing launchable. The plan rides the command as
## [member LaunchAttackCommand.local_plan]. Runs the checks that need the LIVE plan and are cheap to answer
## before anything is queued — is there a plan, is it valid, is somebody's turn
## — and stamps the per-attack seed.
##
## [b]The seed is stamped HERE, not at resolve.[/b] It is an input to the
## resolution, and putting it on the command makes the artifact
## self-describing: (plan + seed) is everything an authority needs to re-resolve
## and compare. `apply_launch_command` copies it onto the plan before calling
## [method AttackPlan.resolve], so "stamp before resolving" still holds.
func build_launch_command(plan: AttackPlan) -> LaunchAttackCommand:
	if plan == null or is_launching:
		push_warning("BattleSystem.launch_attack: no plan, or already launching")
		return null
	if not plan.is_valid():
		push_warning("BattleSystem.launch_attack: invalid plan: %s" % str(plan.validate()))
		return null
	var entity := turn_manager.current_entity if turn_manager != null else null
	if entity == null:
		push_warning("BattleSystem.launch_attack: no current entity")
		return null
	var command := LaunchAttackCommand.new(
			entity.entity_id, plan.to_dict(graph), _seed_source.randi())
	command.local_plan = plan
	return command


## [b]The VALIDATE half of a launch (#545)[/b] — [method CommandApplier._validate]'s
## entry point for a [LaunchAttackCommand], and the one place an attack is
## decided. Returns whether the command may go ahead; the world is untouched
## either way.
##
## [b]This is a gate that also PRODUCES its command's payload[/b], which is what
## makes it unlike every other branch of `_validate`. The attack's real gate —
## resolve, then check affordability — cannot be asked without resolving, and
## the resolution IS the payload. Since #536 resolving costs nothing real (a
## [method CombatWorld.shadow], see [method _compute_record]), so doing it here
## is legal; doing it here is what lets the record be final BEFORE the confirm,
## which is what stopped the authority mutating a full window ahead of every
## peer.
##
## A REPLAY (a populated record) has nothing to compute and nothing left to
## refuse — the attack was decided on the machine that sent it.
func prepare_launch_command(command: LaunchAttackCommand) -> bool:
	if command == null or is_launching:
		return false
	if not command.record.is_empty():
		return true
	var plan := command.local_plan
	var decoded := plan == null
	if decoded:
		# Another seat's intent: plans are seat-local until launch (ADR 0035),
		# so the plan — temp upgrades included — arrives only as the dict. Every
		# refusal below frees what the decode attached to live nodes.
		plan = AttackPlanCodec.from_dict(command.plan, graph, temp_upgrade_catalog)
		if plan == null:
			push_warning("BattleSystem: launch_attack initiate with an undecodable plan")
			return false
	# Re-validated HERE, not only in `build_launch_command`: a command can sit in
	# the queue while the world moves under it (a cascade frees the pivot, the
	# target is captured). An invalidated plan resolves to an EMPTY outcome whose
	# `ap_cost` still defaults to 1, so skipping this spends AP on nothing.
	if not plan.is_valid():
		push_warning("BattleSystem: plan went invalid before apply: %s" % str(plan.validate()))
		if decoded:
			plan.reset()
		return false
	if not _compute_record(plan, command):
		if decoded:
			plan.reset()
		return false
	command.local_plan = plan
	# LAST, and only on the success path: it is what tells the apply half that
	# `local_plan` is the plan this machine resolved. See [member
	# LaunchAttackCommand.computed_here].
	command.computed_here = true
	return true


## Apply [param command] — the [CommandApplier]'s entry point, and the one
## place an attack mutates the world.
##
## [b]ONE launch path (#536).[/b] There used to be two — `_launch_as_authority`,
## which resolved and applied its own outcome against the real world, and
## `_replay_launch`, which reconstructed a record. Every machine now runs the
## same half here:
##
## [codeblock]
## prepare (validate) -> COMPUTE: resolve on a shadow, capture the record
## apply   (mutate)   -> REPLAY:  rebuild that record, land it on the BeatClock
## [/codeblock]
##
## Per #498: [i]"the host becomes a peer of itself; it is the only one that
## computes, not the only one that replays."[/i] Which half a machine ran is a
## payload question, never a peer role (see [LaunchAttackCommand]) — and since
## #545 moved the compute ahead of the confirm, the payload field that answers it
## is [member LaunchAttackCommand.computed_here], not an empty record.
##
## [b]An unprepared command is refused, not quietly computed.[/b] There is no
## compute branch left here to fall into: whoever applies must have run
## [method prepare_launch_command] first, because that is where the confirm sits
## between the two.
##
## [b]One refusal below is NOT pre-empted by validate[/b], and the invariant
## "a confirmed command will apply" is that much weaker for it: on the REPLAY
## branch a malformed [member LaunchAttackCommand.plan] fails
## [method AttackPlanCodec.from_dict] here, having already confirmed. Vetting it
## in [method prepare_launch_command] would mean rebuilding the plan twice per
## replay to catch a corrupt payload that is already corrupt — not worth it, and
## it costs nothing on the wire ([method CommandChannel._on_command_confirmed]
## broadcasts only under [constant NetworkConfig.Role.HOST], which a replaying
## peer is not).
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
	if command.record.is_empty():
		push_warning("BattleSystem: launch_attack applied without prepare_launch_command")
		return false
	var plan: AttackPlan
	if command.computed_here:
		# Carried on the command from `build_launch_command`, never re-read off
		# the seat — the plan this machine resolved is the plan it commits.
		plan = command.local_plan
		if plan == null:
			push_warning("BattleSystem: the prepared plan went away before apply")
			return false
	else:
		# A replay decodes into the same local field and never touches the
		# seat's armed plan: that is this seat's plan-in-progress, not the attacker's.
		plan = AttackPlanCodec.from_dict(command.plan, graph, temp_upgrade_catalog)
		if plan == null:
			return false
		command.local_plan = plan
		# Melee draws off `last_trajectory` / `last_events`, which only a
		# resolve fills in; the stage starts that draw-only resim (#796),
		# stepped, never baked whole before this method returns. The outcome
		# it produces is DISCARDED — the record is what lands (see
		# [AttackRecord]). A stage-less peer pays nothing for it.
		if stage != null:
			stage.prepare_replay(plan)
	# Everyone, authority included, from here down.
	# Seconds are minted here, on THIS machine, at THIS machine's rate for this
	# actor — the one melee rate door (#819/#820). Passed rather than left
	# ambient because [AttackRecord] is pure data with no opinion about seats.
	var outcome := AttackRecord.rebuild(command.record, graph,
			OutcomeSchedule.actor_rate(seat_policy, plan.attacker, presentation_rate_scale))
	@warning_ignore("redundant_await")
	await _commit(plan, outcome)
	return true


## The COMPUTE half — authority only, and the one place in the codebase that
## decides what an attack does. Stamps [param command]'s record and returns
## true, or refuses on affordability and returns false. Runs inside
## [method prepare_launch_command], which is to say inside the VALIDATE half,
## ahead of the confirm (#545) — never inside the apply.
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


## The ranged volley's cost (#957), paid HERE beside AP so every machine —
## authority and mirror alike — deducts it from the same rebuilt command. Owner
## (2026-09-18): *"a shot fired is a shot fired and a shot fired uses ammo"* —
## consumption is per SHOT, never per landing, so a dud still costs (every hit
## the resolve minted is in [param outcome], vetoed or not). Bins drain from the
## plan's effective composition (the wire carries it explicitly); each hit's
## origin leaf is marked fired and remembered on the firer for its turn-end
## reset (the `_fired_nodes_this_turn` seam C2 authored for exactly this call);
## the volleys counter ticks once.
func _consume_volley(plan: RangedAttackPlan, outcome: AttackOutcome) -> void:
	var entity := plan.attacker
	if entity == null:
		return
	var quiver: Quiver = entity.stat_board.arrows if entity.stat_board != null else null
	if quiver != null:
		var counts := plan.effective_ammo_counts()
		for id in counts:
			quiver.take(id, int(counts[id]))
	for hit in outcome.hits:
		# One shot per ARROW: a typed arrow's status hit (#495) shares its
		# arrow's origin and must not burn a second shot. Skipped by CLASS,
		# never by `kind` — a heal-flipped arrow (ADR 0012) is still a shot
		# fired; a status never was one.
		if hit is StatusInstance:
			continue
		var leaf := hit.origin
		if leaf == null or not is_instance_valid(leaf):
			continue
		leaf.mark_shot_fired(1)
		if not entity._fired_nodes_this_turn.has(leaf):
			entity._fired_nodes_this_turn.append(leaf)
	entity.volleys_launched_this_turn += 1


## Can [param plan]'s attacker pay for [param outcome]? Reads the LIVE pools —
## an attack computed on a shadow is still paid for out of the real board.
func _can_afford(plan: AttackPlan, outcome: AttackOutcome) -> bool:
	# The plan's own budget (blade members + temp upgrades) — the one sum a new
	# plan-level cost type joins. Membership and placement are NOT re-judged.
	if plan.budget_overrun() > 0:
		push_warning("BattleSystem.launch_attack: plan over budget by %d" % plan.budget_overrun())
		return false
	if plan.aspect_overrun() > 0:
		push_warning("BattleSystem.launch_attack: plan over its aspect caps by %d" \
				% plan.aspect_overrun())
		return false
	var entity := plan.attacker
	var board: StatBoard = entity.stat_board if entity != null else null
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null and ap_pool.available() < outcome.ap_cost:
		push_warning("BattleSystem.launch_attack: insufficient AP (%d < %d)" \
				% [int(ap_pool.current), outcome.ap_cost])
		return false
	return true


## The APPLY half — what every machine runs, authority included, on the outcome
## rebuilt from the record. There is no longer a second version of this for the
## machine that computed it.
##
## Costs are deducted up front; the plan itself stays live through the whole
## await (#406 — a melee plan's attached temp-upgrade addons must keep
## rendering through the live swing) and is cleared in one place, after.
## `is_launching` — not a live plan — is what blocks a second
## launch during the await window.
##
## [b]Phases overlap, and that is the point.[/b] The arrow is in the air while
## the mutation loop waits out its `arrival_time`, so the health bar, the
## shatter, the fog and the damage number all move on the same beat — they are
## all reading the model, and the model changes when the arrow lands. The rule
## this does not break is [b]never frame-ordered mutation[/b] — see [BeatClock].
## VFX still gates nothing: dropping every frame of the animation leaves the
## applied world identical, because the loop waits on its own timer and not on
## any animation.
func _commit(plan: AttackPlan, outcome: AttackOutcome) -> void:
	is_launching = true
	_in_flight_plan = plan
	in_flight_plan_changed.emit(plan)
	_draining = false
	var entity := plan.attacker
	var board: StatBoard = entity.stat_board if entity != null else null
	var ap_pool: PoolStat = board.action_points if board != null else null
	if ap_pool != null:
		ap_pool.deplete(float(outcome.ap_cost))
	if plan is RangedAttackPlan:
		_consume_volley(plan as RangedAttackPlan, outcome)
	var launched_spell: SpellDef = (plan as MagicAttackPlan).spell if plan is MagicAttackPlan else null
	attack_launched.emit(plan.mode, launched_spell)
	# The stage mounts BEFORE the commit signal (ADR 0027): the director
	# reads [method presenter] inside `attack_committed` to open its shot on
	# the presenter's marker, so the presenter has to exist by then.
	if stage != null:
		stage.mount(plan, outcome)
	# Un-awaited, like every other observer on this path: `_apply_outcome`
	# below is what waits on the beat clock, and anything awaited here would
	# gate the mutation loop.
	attack_committed.emit(outcome, entity)
	# Costs are already deducted; the plan is still live, so an effect can read
	# its targets. Replaces the issue's `_on_battle_start` — there is no battle.
	if plan.attacker != null:
		plan.attacker.dispatch(&"_on_attack_launched", [plan.mode, launched_spell])
	# ADR 0027: one staging path for every mode. The wind-up is the ONLY
	# awaited beat between the commit and the replay; it compiles nothing,
	# reorders nothing, and waits on no animation. A null stage stages 0 s.
	await _stage_windup(plan)
	# The replay starts FIRST and UN-AWAITED, so it runs alongside the
	# mutation loop below: the arrow is in the air while the loop waits out
	# its `arrival_time`. It is a pure observer — the loop waits on its own
	# timer, so a dropped frame cannot change gameplay.
	#
	# The schedule is compiled here when nothing has yet — the blade has to
	# know the rate its hits land on, and this runs BEFORE `_apply_outcome`,
	# where [method OutcomeApplier.apply] would otherwise compile it. The
	# compile is pure and the applier reuses this instance. After the compile,
	# before the play: an observer sizes itself off the schedule and must see
	# the replay's first moving frame, not its second.
	if stage != null and stage.stages(plan):
		if outcome != null and outcome.schedule == null:
			outcome.schedule = OutcomeSchedule.compile(outcome)
		attack_replay_started.emit(outcome)
		# Runs synchronously up to its first await, which is what makes
		# `holds_release` trustworthy on the lines after it: true means
		# "parked, will emit `finished`", false means "already done" — the
		# check that keeps a fully-synchronous stage from emitting into no
		# listener and hanging the launch forever.
		stage.play(plan, outcome)
	# World mutation, on the beat clock. Awaited: `is_launching` gates on the
	# WORLD being finished, never on the animation.
	await _apply_outcome(outcome)
	# Nothing is captured and nothing is confirmed here (#536, then #545). The
	# record was complete before this method was entered — it is the record this
	# pass just replayed — and the confirm went with it, up into
	# [method CommandApplier._drain], where it fires for this verb exactly as it
	# does for the other eight.
	#
	# [signal CommandApplier.command_confirmed] still earns its existence, and
	# this method is the reason: `command_applied` cannot fire until this
	# coroutine returns, so mirroring off THAT would make a peer sit out the
	# host's whole swing before starting its own.
	#
	# Then release. `is_launching` spans the WHOLE action, not just the
	# mutation: it is what blocks a second launch, and the plan stays live
	# behind it. Two ways out, because the two modes want different things:
	#
	#   * MELEE parks on the swing (`stage.holds_release`). A melee plan's
	#     temp-upgrade addons (#406) must keep rendering through the visible
	#     blade, and the ghost the preview animates IS the plan — clearing at
	#     mutation-end would let a player arm and fire again mid-swing with the
	#     previous plan still mounted.
	#   * RANGED/MAGIC releases on `release_beat`, already waited out inside
	#     `_apply_outcome`. Their coordinators own nothing of the plan, so
	#     holding for the drain only bought a lockout for the arrow's
	#     stick-and-fade — three quarters of a second in which the world was
	#     already final. The arrows finish fading under `%AttackVFX` on their
	#     own; see [member release_beat].
	if _stage_holds(plan):
		await stage.finished
	# is_launching flips false BEFORE _reset() (not after) — _reset()'s
	# in_flight_plan_changed(null) re-arms the seat's attack level, whose
	# push refuses mid-swing, and PlayerInputController's gate-refresh
	# listener reads is_launching the instant the plan moves. Clearing it after would have that listener
	# observe a stale "still launching" and never re-enable AttackModeBar.
	# Keep these two adjacent: callers settle on `is_launching` and expect the
	# plan to be cleared by the time it goes false.
	is_launching = false
	_reset()


## The wind-up shape in force — the [member stage]'s, or the authored `.tres`
## with no stage. The camera reads it to time its shot.
func tempo() -> PresentationTempo:
	return stage.tempo() if stage != null else PresentationTempo.shared_default()


## Whether the [member stage]'s play in flight still holds the release.
func _stage_holds(plan: AttackPlan) -> bool:
	return stage != null and stage.holds_release(plan)


## [b]"The record is ready" — the swing beat's one await point, and the seam
## #796 drives.[/b] Returns immediately unless something has declared the
## record outstanding via [method hold_record].
##
## [b]Today this is a satisfied no-op on every path that exists[/b], and it is
## named and awaited anyway. Since #545 the [AttackRecord] is final BEFORE the
## confirm — the authority computes it inside the synchronous
## [method prepare_launch_command], and a mirror receives setup and outcome in
## the same command — so by the time [method _commit] reaches the swing there
## is nothing left to wait for.
##
## It exists so #796 has a seam to cite rather than guess at. When the melee
## resolve moves off the synchronous `_validate` and onto a [WorkerThreadPool],
## the thing that becomes asynchronous is exactly this, and nothing else in
## [method _commit] has to move. Per #559 decision 3 the AUTHORITY has no floor
## here — there is no swing to start without a record, so the form loop holds
## until it exists — while a mirror already holds one and never parks at all.
##
## [b]Awaited on the seated path too.[/b] The typical authority IS the seated
## local player, so a `seats()` early-return would delete this await on the one
## machine #796 needs it on (#559, sharpening on decision 1).
func await_record_ready() -> void:
	if not _record_pending:
		return
	await record_ready


## Declare the in-flight launch's record OUTSTANDING, so the swing beat parks
## in [method await_record_ready] until [method release_record]. Nothing in
## production calls this yet — #796 is what will.
func hold_record() -> void:
	_record_pending = true


## Release a parked swing beat. Idempotent, and a no-op when nothing held.
func release_record() -> void:
	if not _record_pending:
		return
	_record_pending = false
	record_ready.emit()


## The presenter for the launch in flight — whatever answers the contract
## ([method VFXCoordinator.begin_windup] / [method VFXCoordinator.focus_marker]
## / [signal VFXCoordinator.focus_marker_changed], ADR 0027), as the
## [member stage] reports it. Null with no stage, or between launches.
func presenter() -> Node:
	return stage.focus() if stage != null else null


## Stage a committed attack's wind-up (#559, generalised by ADR 0027): the
## presenter focuses, forms, stamps, ramps, flares — whatever its mode's
## picture is — and returns the seconds that takes; then the replay begins.
##
## [b]An awaited beat on its own timer, never a wait on an animation.[/b]
## `begin_windup` starts a Tween and returns the length it staged; the wait
## below is that length on a [BeatClock], so a dropped frame, a muted
## animation or a killed tween cannot move when the replay starts. The clock
## is parked in [member _beat_clock] for the same reason the mutation loop's
## is: [method drain_pending_mutations] must be able to cut a wind-up short on
## scene teardown, or `_commit` sits on a timer belonging to a tree that is
## going away.
##
## [b]This runs for EVERY actor and EVERY mode.[/b] The escape hatch is the
## authored tempo (and the coordinators' default 0.0) — zero-length beats,
## never the sequence's existence. A null [param presenter] (a headless peer)
## stages nothing and still reaches [method await_record_ready]; see that
## method for why the distinction is load-bearing.
##
## Nothing here compiles or touches [OutcomeSchedule]: this shifts WHEN the
## mutation loop starts and changes nothing about what lands or in what order.
func _stage_windup(plan: AttackPlan) -> void:
	var staged: float = stage.begin_windup(plan) if stage != null else 0.0
	if staged > 0.0:
		await _new_beat_clock().advance_to(staged)
		_beat_clock = null
	@warning_ignore("redundant_await")
	await await_record_ready()


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
## the applied world is identical whether or not a [member stage] is wired — so
## making the clock depend on that is exactly the thing that must not matter.
## A fixture that wants the whole outcome on one line says so out loud.
func _apply_outcome(outcome: AttackOutcome) -> void:
	@warning_ignore("redundant_await")
	await OutcomeApplier.apply(outcome, CombatWorld.live(), _new_beat_clock(), allocation_system)
	# The release beat, on the same clock and for the same reasons: instant
	# under `instant_mutation`, and cut short by `drain_pending_mutations`.
	# Melee doesn't want it — it has a whole swing left to watch — and asking
	# for it there would just push the blade's own release out by 0.12 s.
	if release_beat > 0.0 and not _stage_holds(_in_flight_plan):
		@warning_ignore("redundant_await")
		await _beat_clock.advance_to(_beat_clock.elapsed + release_beat)
	_beat_clock = null


## Land every hit the current attack has not landed yet, immediately. Called on
## scene teardown ([method GameRoot._exit_tree]): design B's one real risk is a
## mutation loop interrupted mid-window, which would leave the world valid but
## permanently wrong. No-op when no attack is in flight.
func drain_pending_mutations() -> void:
	_draining = true
	if _beat_clock != null:
		_beat_clock.drain()


## Mint (and park) the clock for one beat of the current launch — the wind-up's
## and the mutation loop's alike. Parked in [member _beat_clock] so
## [method drain_pending_mutations] can reach whichever one is live, and made
## instant once a drain has happened so the beats AFTER it land synchronously
## rather than on a doomed tree's timers.
func _new_beat_clock() -> BeatClock:
	_beat_clock = BeatClock.instant_clock() if instant_mutation or _draining \
			else BeatClock.for_tree(get_tree())
	return _beat_clock


## Forced-deallocation cascade. Runs when a (non-core) node hits 0 HP: the
## depleted node and every node disconnected from the defender's core when
## it leaves are force-dealloc'd. Each cascaded node costs the defender:
##   * 1 wounded SP — currency exchange (invested SP → wounded, reserves a
##     slot in the pool until healed, mirrors PoE's reserved-pool slots).
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
func _on_node_depleted(node: SkillNode, source: HitInstance = null) -> void:
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


## Entity-death cascade wave (#837). `AllocationSystem.deallocate_all_owned`
## strips a dying entity's whole board un-staggered and MUST keep the core
## last (it is the only path that ever force-deallocates a core — islanding
## checks need it gone last). The wanted VISUAL wave is the opposite: core
## FIRST, rippling outward — so this computes and announces that layering
## separately, and `deallocate_all_owned` keeps iterating however it needs to;
## the delay map `AllocationVFX` builds off `cascade_started` is keyed by node,
## so the two orders never have to agree (decision #2 on the issue).
##
## Subscribed to `entity_dying` (the PRE-cleanup phase — the corpse still owns
## its nodes) rather than `entity_died` (the CLEANUP phase, where
## `AllocationSystem`'s own handler runs the strip): `Events`' own two-phase
## contract guarantees every `entity_dying` handler finishes before any
## `entity_died` handler runs, so the wave is announced before the strip with
## no new cross-system reference and no dependence on scene connection order.
##
## Reuses [method _cascade_layers] unchanged, with the core as impact and every
## other currently-owned node as the cascade set — same BFS, same orphan
## handling for a disconnected owned island (issue acceptance #5).
func _on_entity_dying(entity: Entity) -> void:
	if entity == null or graph == null:
		return
	var core := entity.core_location
	if core == null:
		return
	var owned: Array[SkillNode] = []
	for n in graph.get_skill_nodes():
		if n != core and n.owned_by == entity:
			owned.append(n)
	if owned.is_empty():
		return
	var layers: Array = _cascade_layers(core, owned)
	cascade_started.emit(layers, entity)


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
